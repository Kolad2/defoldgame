# Recast Navigation sources

Upstream: https://github.com/recastnavigation/recastnavigation

Release: **v1.6.0**

Commit: `6dc1667f580357e8a2154c28b7867bea7e8ad3a7`

The complete `Recast`, `Detour`, `DetourCrowd`, `DetourTileCache` and
`DebugUtils` module directories are copied into `source/recastnavigation/`,
including their original `Include`, `Source` and `CMakeLists.txt` files.
These upstream files are unmodified. The upstream zlib license is preserved
at `source/recastnavigation/License.txt` and in source headers. The
packaged extension also carries the license in `include/recastnavigation-license.txt`.

This extension's CMake project compiles all five modules into one static `recast`
library. Build `detour_package` to copy the archive into `lib/<platform>/`
and the original public headers into `include/`. See
[the CMake/CLion workflow](BUILDING.md).
CMake separately builds the integration files under `source/runtime` into
`detour_runtime.lib` (`libdetour_runtime.a` on Android). That archive contains
no upstream objects. Defold links both archives and compiles only the empty
`src/extension.cpp` placeholder required by Extender. All implementations are
outside the extension's `src` tree, so they cannot be compiled twice.
Keep packaged headers and libraries in sync; rebuild the runtime archive with
the matching Defold SDK when upgrading the engine. `lib/<platform>/defold-sdk.txt`
records the SDK revision used for packaging.
The manifest's `upload/extensions/detour/include` path is relative to the server job
directory. If renaming or relocating the extension folder, update it too.
RecastDemo, its UI dependencies and upstream tests are not runtime libraries
and are not included in the extension.

Defold-specific code lives outside the upstream directory:

- `source/runtime/detour.cpp`: Lua API, mesh loading, query and crowd integration.
- `source/runtime/navmesh_debug.cpp` and `.h`: upstream `duDebugDraw` adapter.
- `source/runtime/navmesh_component.cpp`: component resource loading and runtime debug rendering.
- `source/runtime/navmesh_data.h`: compiled-resource and MSET validation/loader.
- `source/editor/navmesh_preview.cpp`: editor JNI adapter linked to the core archive.
- `editor/` and Java files in `source/editor/`: Defold resource/editor integration.

The editor library in `plugins/lib/x86_64-win32` compiles only the JNI adapter
and links the same CMake `recast` archive that is packaged for the game. Upstream
sources are compiled once per CMake profile, with no duplicate source list for
the editor. The editor and game use separate binaries and processes; static
linking places the required machine code in each consumer. Java/Clojure editor
code is not linked into the game. See `editor/README.md` for host requirements.

The new modules are available to C++ code; their complete APIs are not
automatically exposed to Lua. Existing query/crowd methods remain available,
with `get_debug_lines` added for runtime visualization.

When updating, replace all five modules from the same upstream release in
`extensions/detour/source/recastnavigation`, update the commit here, rebuild `detour_package`
for each supported platform, and check the example's existing `assets/navmesh.bin`
before accepting the update. The Windows package target rebuilds the editor
DLL and JAR as needed; Android packaging updates only the Android game library.
Do not patch upstream files for Defold integration.
