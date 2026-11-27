# The plugin links the very same recast target that is packaged for the game.
# Only the JNI adapter is compiled here; upstream .cpp files are not listed again.
# DefoldSDK.cmake has already resolved the shared Defold installation.
if(NOT EXISTS "${DETOUR_DEFOLD_DIR}/config")
    message(FATAL_ERROR "Set DETOUR_DEFOLD_DIR to your installed Defold directory, or disable DETOUR_BUILD_EDITOR.")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${DETOUR_DEFOLD_DIR}/config")
file(READ "${DETOUR_DEFOLD_DIR}/config" defold_config)
string(REGEX MATCH "editor_sha1[ \t]*=[ \t]*([a-fA-F0-9]+)" unused "${defold_config}")
set(editor_sha "${CMAKE_MATCH_1}")
string(REGEX MATCH "jdk[ \t]*=[^\r\n]*/packages/([^\r\n]+)" unused "${defold_config}")
string(STRIP "${CMAKE_MATCH_1}" jdk_name)
if(NOT editor_sha OR NOT jdk_name)
    message(FATAL_ERROR "Cannot read editor_sha1 or jdk from the installed Defold config.")
endif()
set(editor_api "${DETOUR_DEFOLD_DIR}/packages/defold-${editor_sha}.jar")
set(editor_jar_tool "${DETOUR_DEFOLD_DIR}/packages/${jdk_name}/bin/jar.exe")
foreach(tool IN ITEMS "${editor_api}" "${editor_jar_tool}")
    if(NOT EXISTS "${tool}")
        message(FATAL_ERROR "Defold editor build tool not found: ${tool}")
    endif()
endforeach()

# The editor's trimmed runtime does not include JNI headers or javac. A full
# JDK supplies the stable JNI headers; the pinned ECJ compiler reads the editor
# API's Java 25 classes and writes Java 21 bytecode, as the existing plugin did.
set(DETOUR_JNI_HOME "$ENV{JAVA_HOME}" CACHE PATH "JDK/JBR root providing include/jni.h")
file(GLOB clion_jdks LIST_DIRECTORIES true "$ENV{ProgramFiles}/JetBrains/CLion*/jbr")
set(jni_hints "${DETOUR_JNI_HOME}/include" "${DETOUR_DEFOLD_DIR}/packages/${jdk_name}/include")
foreach(jdk IN LISTS clion_jdks)
    list(APPEND jni_hints "${jdk}/include")
endforeach()
find_path(DETOUR_JNI_INCLUDE_DIR jni.h HINTS ${jni_hints} REQUIRED)
find_path(DETOUR_JNI_PLATFORM_INCLUDE_DIR jni_md.h HINTS "${DETOUR_JNI_INCLUDE_DIR}/win32" REQUIRED)
cmake_path(GET DETOUR_JNI_INCLUDE_DIR PARENT_PATH jni_java_home)
find_program(DETOUR_EDITOR_JAVA java.exe HINTS "${jni_java_home}/bin" NO_DEFAULT_PATH REQUIRED)

set(DETOUR_ECJ_JAR "${DETOUR_BUILD_CACHE_DIR}/cmake-tools/ecj-3.43.0.jar"
    CACHE FILEPATH "Eclipse Java compiler JAR (downloaded when missing)")
set(ecj_sha256 c786468c65e906498e7e36ece4e0d04c6d3dd34c9a61b34a3a5b512801911a82)
if(NOT EXISTS "${DETOUR_ECJ_JAR}")
    cmake_path(GET DETOUR_ECJ_JAR PARENT_PATH ecj_directory)
    file(MAKE_DIRECTORY "${ecj_directory}")
    message(STATUS "Downloading Eclipse Java compiler 3.43.0 (build tool only)")
    file(DOWNLOAD
        "https://repo.maven.apache.org/maven2/org/eclipse/jdt/ecj/3.43.0/ecj-3.43.0.jar"
        "${DETOUR_ECJ_JAR}" TLS_VERIFY ON
        EXPECTED_HASH "SHA256=${ecj_sha256}")
endif()
file(SHA256 "${DETOUR_ECJ_JAR}" actual_ecj_sha256)
if(NOT actual_ecj_sha256 STREQUAL ecj_sha256)
    message(FATAL_ERROR "DETOUR_ECJ_JAR must be the unmodified Eclipse compiler 3.43.0 JAR.")
endif()

add_library(navmesh_editor SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/source/editor/navmesh_preview.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/source/editor/navmesh_constructor.cpp")
target_link_libraries(navmesh_editor PRIVATE recast)
target_include_directories(navmesh_editor PRIVATE "${DETOUR_JNI_INCLUDE_DIR}" "${DETOUR_JNI_PLATFORM_INCLUDE_DIR}")
target_compile_features(navmesh_editor PRIVATE cxx_std_11)
target_compile_definitions(navmesh_editor PRIVATE _CRT_SECURE_NO_WARNINGS _ITERATOR_DEBUG_LEVEL=0)
target_compile_options(navmesh_editor PRIVATE /W3 /EHsc /GR-)
set_target_properties(navmesh_editor PROPERTIES
    MSVC_RUNTIME_LIBRARY MultiThreaded
    CXX_EXTENSIONS OFF
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/editor/$<CONFIG>"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/editor/$<CONFIG>"
)

set(editor_sources_root "${CMAKE_CURRENT_SOURCE_DIR}/source/editor")
file(GLOB_RECURSE editor_java_sources CONFIGURE_DEPENDS "${editor_sources_root}/*.java")
set(editor_jar "${CMAKE_CURRENT_BINARY_DIR}/editor/$<CONFIG>/navmesh-editor.jar")
add_custom_command(OUTPUT "${editor_jar}"
    COMMAND "${CMAKE_COMMAND}"
        "-DEDITOR_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}/editor/$<CONFIG>"
        "-DPROJECT_BINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "-DEDITOR_SOURCE_DIR=${editor_sources_root}"
        "-DEDITOR_JAVA=${DETOUR_EDITOR_JAVA}"
        "-DEDITOR_JAR_TOOL=${editor_jar_tool}"
        "-DEDITOR_API=${editor_api}"
        "-DEDITOR_ECJ=${DETOUR_ECJ_JAR}"
        -P "${CMAKE_CURRENT_LIST_DIR}/BuildEditorJar.cmake"
    DEPENDS ${editor_java_sources} "${editor_api}" "${DETOUR_ECJ_JAR}"
        "${CMAKE_CURRENT_LIST_DIR}/BuildEditorJar.cmake"
    COMMENT "Compiling editor/resource-builder Java code into navmesh-editor.jar"
    VERBATIM
)
add_custom_target(navmesh_editor_java DEPENDS "${editor_jar}")
message(STATUS "Editor plugin enabled; Defold API ${editor_sha}")
