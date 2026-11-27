cmake_minimum_required(VERSION 3.24)
project(defold_detour VERSION 1.6.0 LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
# Match the engine's MT_StaticRelease ABI in every profile, including Debug.
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded)
set(DETOUR_EXTENSION_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE PATH
    "Defold extension directory receiving game libraries and editor artifacts")
set(DETOUR_BUILD_CACHE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.build/dependencies" CACHE PATH
    "Downloaded Defold SDK headers and editor compiler cache")
set(RECAST_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/source/recastnavigation")

# This archive contains only unmodified upstream modules, never Defold/JNI code.
set(RECAST_MODULES Recast Detour DetourCrowd DetourTileCache DebugUtils)
set(RECAST_SOURCES)
set(RECAST_INCLUDE_DIRS)
foreach(module IN LISTS RECAST_MODULES)
    file(GLOB module_sources CONFIGURE_DEPENDS "${RECAST_ROOT}/${module}/Source/*.cpp")
    list(APPEND RECAST_SOURCES ${module_sources})
    list(APPEND RECAST_INCLUDE_DIRS "${RECAST_ROOT}/${module}/Include")
endforeach()

if(ANDROID)
    if(NOT ANDROID_ABI STREQUAL "arm64-v8a")
        message(FATAL_ERROR "This Android profile requires ANDROID_ABI=arm64-v8a.")
    endif()
    set(DETOUR_PLATFORM arm64-android)
elseif(WIN32 AND CMAKE_SIZEOF_VOID_P EQUAL 8)
    if(NOT MSVC)
        message(FATAL_ERROR
            "Defold Windows libraries require the MSVC ABI. In CLion select the "
            "Visual Studio toolchain and a windows-* preset; do not use MinGW.")
    endif()
    set(DETOUR_PLATFORM x86_64-win32)
else()
    message(FATAL_ERROR "Configured platforms: Windows x64 (MSVC ABI), Android arm64 (NDK).")
endif()

add_library(recast STATIC ${RECAST_SOURCES})
target_compile_features(recast PUBLIC cxx_std_11)
# Read headers directly from each upstream module's Include directory.
# PUBLIC propagates this list to detour_runtime and navmesh_editor via linking.
target_include_directories(recast PUBLIC ${RECAST_INCLUDE_DIRS})
set_target_properties(recast PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    CXX_EXTENSIONS OFF
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib"
    # The engine uses the static release CRT even for a debug variant.
    MSVC_RUNTIME_LIBRARY MultiThreaded
)
if(MSVC)
    target_compile_definitions(recast PRIVATE _CRT_SECURE_NO_WARNINGS _ITERATOR_DEBUG_LEVEL=0)
    target_compile_options(recast PRIVATE /W3 /GR-)
else()
    target_compile_options(recast PRIVATE -fno-exceptions -fno-rtti -fvisibility=hidden)
endif()

include("${CMAKE_CURRENT_LIST_DIR}/cmake/DefoldSDK.cmake")
add_library(detour_runtime STATIC
    source/runtime/detour.cpp
    source/runtime/navmesh_debug.cpp
    source/runtime/navmesh_debug.h
    source/runtime/navmesh_component.cpp
    source/runtime/navmesh_runtime.h
    source/runtime/navmesh_data.h
)
# Linking static targets supplies include directories and build ordering; it
# does not merge recast's object files into detour_runtime's archive.
target_link_libraries(detour_runtime PRIVATE recast)
target_include_directories(detour_runtime SYSTEM PRIVATE ${DETOUR_SDK_INCLUDE_DIRS})
target_compile_features(detour_runtime PRIVATE cxx_std_11)
set_target_properties(detour_runtime PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    CXX_EXTENSIONS OFF
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib"
    MSVC_RUNTIME_LIBRARY MultiThreaded
)
if(MSVC)
    target_compile_definitions(detour_runtime PRIVATE DM_PLATFORM_WINDOWS DLIB_LOG_DOMAIN="DETOUR"
        _CRT_SECURE_NO_WARNINGS _ITERATOR_DEBUG_LEVEL=0 NOMINMAX WINVER=0x0600)
    # Defold 1.14.1's NDEBUG logging macros use GNU named variadic arguments.
    # Keep SDK assertions/logging enabled for MSVC without patching SDK headers.
    # Release still uses /O2 and /MT; the pure upstream target is unaffected.
    target_compile_options(detour_runtime PRIVATE /W3 /GR- /EHsc /UNDEBUG)
else()
    target_compile_definitions(detour_runtime PRIVATE DM_PLATFORM_ANDROID)
    target_compile_options(detour_runtime PRIVATE -fno-exceptions -fno-rtti -fvisibility=hidden)
endif()

# Extender rejects an extension without sources. Build its empty translation
# unit here too, while Defold compiles only this placeholder before final linking.
add_library(detour_extension OBJECT src/extension.cpp)

set(editor_default OFF)
if(WIN32 AND NOT CMAKE_CROSSCOMPILING)
    set(editor_default ON)
endif()
option(DETOUR_BUILD_EDITOR "Build the host editor JNI DLL and Java plugin" ${editor_default})
set(package_dependencies recast detour_runtime detour_extension)
set(package_editor_arguments)
set(package_windows_arguments)
if(MSVC)
    cmake_path(GET CMAKE_LINKER PARENT_PATH linker_directory)
    find_program(DETOUR_DUMPBIN dumpbin HINTS "${linker_directory}" REQUIRED)
    list(APPEND package_windows_arguments "-DDETOUR_DUMPBIN=${DETOUR_DUMPBIN}")
endif()
if(DETOUR_BUILD_EDITOR)
    if(NOT DETOUR_PLATFORM STREQUAL "x86_64-win32")
        message(FATAL_ERROR "Build the editor plugin with a Windows host preset, not an Android toolchain.")
    endif()
    include("${CMAKE_CURRENT_LIST_DIR}/cmake/EditorPlugin.cmake")
    list(APPEND package_dependencies navmesh_editor navmesh_editor_java)
    list(APPEND package_editor_arguments
        "-DEDITOR_DLL=$<TARGET_FILE:navmesh_editor>"
        "-DEDITOR_JAR=${editor_jar}"
    )
endif()

# Always stage with copy-if-different so switching profiles refreshes the
# packaged binaries. Public headers remain in their original module directories.
add_custom_target(detour_package ALL
    COMMAND "${CMAKE_COMMAND}"
        "-DRECAST_ROOT=${RECAST_ROOT}"
        "-DRECAST_ARCHIVE=$<TARGET_FILE:recast>"
        "-DRUNTIME_ARCHIVE=$<TARGET_FILE:detour_runtime>"
        "-DDETOUR_SDK_SHA=${detour_sdk_sha}"
        "-DDETOUR_EXTENSION_DIR=${DETOUR_EXTENSION_DIR}"
        "-DDETOUR_PLATFORM=${DETOUR_PLATFORM}"
        ${package_windows_arguments}
        ${package_editor_arguments}
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/PackageDetour.cmake"
    DEPENDS ${package_dependencies}
    COMMENT "Publishing separate core/runtime libraries and enabled editor artifacts"
    VERBATIM
)

message(STATUS "Defold platform: ${DETOUR_PLATFORM}")
message(STATUS "Build target detour_package to update ${DETOUR_EXTENSION_DIR}")
