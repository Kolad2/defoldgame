# Build detour with CMake / CLion

Open this `detour` folder in CLion. You can also open the parent Defold project,
whose root CMakeLists only calls `add_subdirectory(extensions/detour)`. The CMake project builds
all C++ code: the five upstream modules, Lua bindings, runtime component and
editor JNI bridge. It also builds the Java plugin JAR. The outputs stay separate:

```text
extensions/detour/
  CMakeLists.txt         # standalone build definition
  cmake/                 # SDK, editor and packaging helpers
  .build/                # ignored build products and downloaded dependencies
  source/
    recastnavigation/    # unchanged upstream modules -> recast.lib
    runtime/             # Lua API, debug adapter, component -> detour_runtime.lib
    editor/              # JNI and Java -> navmesh_editor.dll / navmesh-editor.jar
  src/extension.cpp      # empty source required by Defold's build service
  include/               # packaged upstream public headers
  lib/x86_64-win32/
    recast.lib
    detour_runtime.lib
    defold-sdk.txt        # engine SDK revision used for the runtime archive
  plugins/               # packaged editor DLL/JAR
```

`recast.lib` contains only original upstream code. The runtime archive contains
only Defold integration; it does not embed the core archive. The editor DLL
links the same `recast` target as the game and does not link `detour_runtime`.

On Windows:

1. In **Settings > Build, Execution, Deployment > Toolchains**, create/select
   a **Visual Studio** toolchain named **Visual Studio**, with architecture
   **amd64**. Visual Studio Build Tools 2022 with C++ and a Windows SDK are
   sufficient. The bundled MinGW toolchain is not compatible with the Windows
   game library's MSVC ABI; CMake rejects it.
2. For the parent example project, enable its **windows-release** preset in
   **Settings > Build, Execution, Deployment > CMake**. Its `CMakePresets.json`
   stays at the project root. When opening this extension alone, create a
   Release profile using the **Visual Studio** toolchain and a build directory
   such as `.build/cmake/windows-release`. Presets are optional.
3. Select the **detour_package** target and your Release profile, then
   use **Build** (`Ctrl+F9`). This builds and publishes
   `extensions/detour/lib/x86_64-win32/recast.lib` and `detour_runtime.lib`,
   the headers in `extensions/detour/include`,
   the upstream license, `extensions/detour/plugins/lib/x86_64-win32/navmesh_editor.dll`,
   and `extensions/detour/plugins/share/navmesh-editor.jar`.
4. Restart Defold after replacing a loaded editor DLL/JAR, then build/run your
   game in Defold or with your project's launcher.

`DETOUR_BUILD_EDITOR` defaults to enabled on Windows. The installed Defold is found
through `DEFOLD_HOME`, or `../../../../Defold` relative to this extension folder
(the layout used by this example). On another machine or in another directory,
set `DEFOLD_HOME` or the `DETOUR_DEFOLD_DIR` CMake option to the installation.
These installation paths belong in local CLion settings or an ignored
`CMakeUserPresets.json`, not in the shared presets.
The runtime uses the installed engine's exact SDK revision. CMake downloads only
the official `defoldsdk_headers.zip` into ignored `extensions/detour/.build/dependencies/defold-sdk/<engine-sha>`;
no engine libraries or SDK tools are needed to create the static archive.
For offline builds, set `DETOUR_DEFOLD_SDK_ROOT` to an extracted `defoldsdk`
directory containing `sdk/include/dmsdk/sdk.h`. `DETOUR_DEFOLD_SDK_SHA` can
explicitly select an engine revision instead of reading the installation.
Rebuild **detour_package** when upgrading Defold: the runtime archive is tied
to the SDK API/ABI, whereas the pure core archive has no Defold dependency.
JNI headers and a Java runtime are found in the installed CLion's JBR, or in
`JAVA_HOME` / `DETOUR_JNI_HOME` (JDK/JBR 21+). The first configure downloads the
pinned Eclipse Java compiler 3.43.0 into ignored `extensions/detour/.build/dependencies/cmake-tools`; for offline
builds, set `DETOUR_ECJ_JAR` to an existing copy. Its SHA-256 is verified. The
compiler reads the installed editor's Java API and emits Java 21 classes.
Build tools and editor dependencies are not packaged into the game.

The **recast** target builds only the core archive. **detour_runtime** builds
the Lua API and game component, **navmesh_editor** builds the JNI DLL using
the core archive, and **navmesh_editor_java** builds the JAR. Building a single
target builds its dependencies but does not publish into the extension.
The default **detour_package** target builds and publishes all enabled outputs.
To build only the game libraries, configure with `DETOUR_BUILD_EDITOR=OFF`.

Use the parent's **windows-debug** preset or a local Debug profile for
unoptimized library code. Both Windows configurations use
the static release CRT (`/MT`) and `_ITERATOR_DEBUG_LEVEL=0`, matching the
engine's `MT_StaticRelease` ABI. The JNI DLL uses the same static CRT so it
can link the exact same core archive. CMake checks the compiled game archives'
CRT directives before publishing; `/MD` or `/MTd` archives are rejected.
The runtime integration keeps assertions and
SDK logging enabled even in Release: the current SDK's `NDEBUG` logging macros
use GNU syntax unsupported by MSVC. Release code remains optimized; upstream
sources and SDK headers are not patched. Debug and Release publish to the same paths:
the last `detour_package` build is the version used by Defold. Do not publish
two profiles simultaneously. The parent presets use `build/cmake/<preset>/`;
for standalone builds, use `.build/cmake/<profile>/` inside this folder.
Downloaded tools/SDK headers live under this extension's
`.build/dependencies/`; override `DETOUR_BUILD_CACHE_DIR` to share another cache.
Hidden `.build` folders stay out of Defold's resource tree and Git.

From an **x64 Native Tools Command Prompt for VS 2022**, with CMake and Ninja
on PATH, run from this folder without any presets:

```text
cmake -S . -B .build/cmake/windows-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build .build/cmake/windows-release --target detour_package
```

From the parent example project, the existing commands are:

```text
cmake --preset windows-release
cmake --build --preset windows-release
```

For Android arm64, install an Android NDK compatible with your Defold version,
set `ANDROID_NDK_HOME` to its directory, and reload the parent project's presets. The
**android-arm64-release** profile then becomes available and produces
`extensions/detour/lib/arm64-android/librecast.a` and `libdetour_runtime.a` through the same
**detour_package** target.
This profile disables the host editor build and uses the NDK toolchain,
`arm64-v8a`, API 21, and position-independent code. Build the Windows profile
for the editor plugin, then the Android profile for the game library.
It requires CMake/Ninja and the NDK on the build host; the Windows compiler
cannot build the Android archive. Windows x64 is the supplied prebuilt platform;
build the archive for any additional target before bundling it in Defold.

The original sources and module CMake files remain unchanged in
`extensions/detour/source/recastnavigation`. Keep Defold-specific changes in
`extensions/detour/source/runtime` or `extensions/detour/source/editor`; do not patch upstream files.
Packaged headers are copies of the upstream originals. Commit the updated
archives, headers and editor artifacts together so users of the extension can build
games without CMake.
The `extensions` folder is exported through Defold's `library.include_dirs`.
Defold compiles only the empty `src/extension.cpp` placeholder and links both
precompiled game libraries. `source` is outside its automatic native-source
collection, so none of the implementations is recompiled on the server.
Changing either packaged library requires relinking the custom Defold engine.
The core is compiled once per CMake profile, and both consumers use the same
archive. Static linking places the required machine code into each executable
or DLL; no second copy of the upstream sources is compiled for the editor.
The JNI code, editor Java classes, and Clojure UI are not linked into the game.
The `.navmesh` resource builder embeds the mesh and display settings in `.navmeshc`.
The native game component owns the mesh, query and crowd and renders its debug
geometry. No editor DLL/JAR is required by the running game.
See [the editor instructions](editor/README.md).


## Copying to another project

Copy the complete `detour` folder into `extensions/detour` in the destination
Defold project, including `CMakeLists.txt` and `cmake/`.
Generated `.build/` and local `.idea/` directories are not needed.
Open the copied folder in CLion and configure the installed Defold/JDK paths.
The default `detour_package` destination is the copied extension itself; it
does not reference the original project.

To build from a parent project, add `add_subdirectory(extensions/detour)` to its CMakeLists.
Presets and CLion profiles belong to that parent project or your local IDE setup;
they are not required when copying or building this extension standalone.
Keep the project-relative location `extensions/detour`. Templates, materials,
Bob resource builders and the manifest use this fixed path. Require the Lua
render helper as `extensions.detour.debug`; the native Lua API remains `detour`.
