# NavMesh and NavMeshConstructor editor components

Tested with Defold **1.14.1**, Windows x86-64. The extension lives in the
project; no changes to the installed editor are needed.

## Bake a model with NavMeshConstructor

Open `example/navmesh_constructor.go` and select **constructor** in Outline.
The component is embedded in the game object, so its settings and **Запечь**
(Bake) button appear directly in Properties. The level and generated navigation
surface appear together in Defold's normal scene viewport.

1. Add **NavMeshConstructor** using **Add Component** on a game object.
2. Set **Source** to a `.model` resource. The model supplies the geometry and
   its materials; it can reference `.glb` or `.gltf`, including external buffers.
3. Set **Output** to a project path ending in `.bin`, for example
   `/assets/navigation/level.bin`.
4. Adjust the Recast parameters. The preview updates after committing a value.
5. Scroll to the bottom of Properties and press **Запечь**. This creates or
   replaces only the specified `.bin`; changing parameters alone does not write it.
6. Select that `.bin` in the **Source** of a normal NavMesh component/resource.

Alternatively, create a `.navmeshconstructor` resource (see
`example/level.navmeshconstructor`) and use **Add Component File**. Open that
resource to edit its shared settings. An empty Output on a standalone resource
saves a `.bin` beside it with the same base name. An embedded component requires
an explicit Output, so multiple constructors on one game object can have distinct files.

The bake uses Defold's imported, selected model geometry in its static/rest pose.
Model node transforms, mirrored winding and the `.model` mesh selection are
included. Game object/component transforms position the editor preview; the
saved mesh stays in model-local coordinates. Give the consuming NavMesh the
same game object/component transform. Animated deformation is not baked.

All fifteen generator parameters are available: Cell Size/Height, Tile Size,
Border Size, Max Slope, Walkable Height/Climb/Radius, Max Edge Length,
Max Simplification Error, Min/Merge Region Size, Max Vertices Per Poly,
Detail Sample Distance and Detail Sample Max Error. Tooltips explain units.
Height and climb are in **vertical cells**; radius and edge length are in
**horizontal cells**. Min/Merge Region Size are squared to obtain region area.
Tile Size `0` builds a single mesh; a positive size builds tiles.

The supplied `level.navmeshconstructor` and embedded `navmesh_constructor.go`
are tuned for `level.model`: Cell Size/Height `0.1`, Walkable Climb `16`
(1.6 model units), Walkable Radius `13` (1.3 units), Min Region Size `100`,
Tile Size `0`, and Border Size `0`. The model's stair rises are about
1.25–1.53 units; its lowest isolated boxes are about 3.35 units tall.
This keeps both staircases connected and removes navigation from isolated
box and pillar tops. Single-mesh baking lets the region filter see whole
islands; tiled builds preserve regions that touch tile borders. Geometry
intersecting the sloped bridge may still be reachable from that bridge.
These are example-specific settings, not universal character dimensions.

Preview Mode shows NavMesh, BV Tree, solid/walkable/compact heightfields,
regions, distance field, raw/simplified contours, polygon mesh or detail mesh.
Show Source, surface/edge toggles, color, opacity, height offset and X Ray affect
display only. Very large intermediate previews fall back to the navigation
surface with a message in Status. The binary remains a RecastDemo MSET v1 file,
compatible with the existing NavMesh resource and Detour runtime.

The baker and its preview run only in the editor. A constructor attached to a
game object compiles to a tiny empty script component with no callbacks. Its
source model, settings and native/Java/Clojure baking code are not added as
runtime dependencies. The normal NavMesh resource embeds the baked data for the game.

## Use

Open `example/example.collection`. Its `navmesh_preview` game object references
`example/level.navmesh`, which reads the existing `/assets/navmesh.bin`.
You can also open the `.navmesh` file by itself to inspect only the navigation surface.

To add another preview, create a **NavMesh** resource in Assets, set **Source**
to a RecastDemo `.bin`, and add that resource as a component to a game object.

- **Source**: RecastDemo MSET v1, Detour tile version 7, little-endian,
  32-bit polygon references (the format used by this extension).
- **Color**: shared tint for the surface and edges.
- **Show Surface / Show Edges**: independently toggle filled triangles and lines.
- **Surface Opacity**: multiplier for the filled surface's alpha, from 0 to 1.
- **Height Offset**: visual Y offset to avoid overlap with the floor; default 0.03.
- **X Ray**: draw through the level geometry. Disabled by default.

The preview and runtime debug rendering follow the game object and component
transforms. Runtime path/crowd positions are converted between world and mesh
coordinates; height offset affects display only.
Changes to the source file refresh the preview when Defold synchronizes resources.
Missing, truncated, and incompatible source files report errors on the component.

No `.buffer` or `.glb` is generated. The native editor bridge loads the actual
NavMesh through Detour and calls upstream `duDebugDrawNavMesh`. The editor draws
its triangles and lines. Off-mesh connections are included in the line view;
all lines use the selected tint rather than upstream's per-primitive colors.

## Runtime component

Building produces an `NVM2` `.navmeshc` containing the complete source mesh,
all display properties and material dependencies. The game component loads
it through Detour and owns a query/filter/crowd for each component instance.
The example no longer reads `/assets/navmesh.bin` from Lua or lists `/assets`
under custom resources.

```lua
local query = detour.get("/navmesh_preview#navmesh")
local path = query:find_path(start, finish)
local crowd = query:create_crowd(1.0)
query:set_debug_enabled(sys.get_engine_info().is_debug)
local settings = query:get_debug_settings()
```

Debug rendering uses Color, Show Surface, Show Edges, Surface Opacity,
Height Offset and X Ray from the component resource. The example render script
calls `extensions.detour.debug` with its world camera. A custom renderer must initialize
and draw this module's predicates and declare the two materials in its `.render`
file; see `example/navmesh.render` and the main README. `render.draw_debug3d()`
alone cannot draw this component's filled surfaces.

Do not delete a component-owned query manually. The game object owns it and
invalidates Lua handles on deletion or resource reload. Obtain a new query
and recreate its crowd after hot reload. Separate components have separate
crowds and filters. World positions follow component transforms; crowd sizes
and speeds use local units, so unit scale is recommended.

Both the editor build pipeline and Bob support `.navmesh`. The editor-only
DLL and JAR are not runtime dependencies of the exported game.

## Files and rebuilds

- `editor/src/navmesh.clj`: resource registration, properties, scene rendering.
- `editor/src/navmesh_constructor.clj`: constructor inspector, model scene geometry, preview and Bake button.
- `editor/resources/templates/template.navmeshconstructor`: constructor defaults.
- `source/editor/navmesh_constructor.cpp`: Recast generation and debug geometry, linked to the same core archive.
- `source/editor/com/defold/navmesh/NavMeshConstructor.java`: short-lived JNI sessions and atomic `.bin` writing.
- `source/editor/com/dynamo/bob/pipeline/NavMeshConstructorBuilder.java`: editor-only component's empty runtime placeholder.
- `editor/resources/templates/template.navmesh`: defaults for new resources.
- `source/editor/navmesh_preview.cpp`: JNI bridge to upstream Detour/DebugUtils.
- `source/editor/com/defold/navmesh/NavMeshPreview.java`: loads the host library.
- `source/editor/com/defold/navmesh/NavMeshResource.java`: shared editor/Bob binary writer.
- `source/editor/com/dynamo/bob/pipeline/NavMeshBuilder.java`: Bob resource builder.
- `plugins/share/navmesh-editor.jar`: prebuilt Java plugin.
- `plugins/lib/x86_64-win32/navmesh_editor.dll`: prebuilt Windows editor library.
- `source/runtime/navmesh_component.cpp`: runtime resource, component and GPU debug rendering.
- `source/runtime/navmesh_data.h`: compiled-resource and MSET validation/loader.
- `debug.lua`, `resources/navmesh*.material`: render integration and materials.

The root CMake project builds the unmodified upstream sources in
`extensions/detour/source/recastnavigation` into a single static `recast` archive. The game
package receives that archive, and the editor JNI DLL links the very same
CMake target. Only the editor's own JNI adapters are compiled for the DLL;
there is no second compilation of upstream sources for the editor. The two
processes still have separate copies of the statically linked machine code.

On Windows, `detour_package` builds and publishes the core library, separate
`detour_runtime.lib`, headers, JNI DLL, and Java JAR together. The runtime
archive contains the Lua API and game resource/component code, compiled
against the installed Defold SDK; it contains neither upstream nor JNI objects.
Clojure UI code stays as source, loaded by the
editor. Defold's own Build does **not** invoke CMake, so run `detour_package`
after editing native or Java code.

The supplied editor binary supports Windows x86-64. Other editor hosts need
their own JNI library (`.so`/`.dylib`) built from the same adapter and upstream
sources. This host limitation does not limit the game's target platforms.
Restart the editor after replacing a JAR or native editor library. Clojure
plugins use editor internals; check compatibility when upgrading Defold.

### Building from CLion

Open the parent project in CLion, select **windows-release** or **windows-debug**
and build **detour_package**. When opening `detour` alone, create a local
Release/Debug profile with the Visual Studio toolchain; no preset is required.
See [setup, commands and copying the extension](../BUILDING.md).
The root presets use the **Visual Studio** toolchain. `DETOUR_BUILD_EDITOR`
defaults to enabled on Windows, including standalone builds.
The DLL links the game's MSVC-ABI archive and uses the static release CRT
(`/MT`) with `_ITERATOR_DEBUG_LEVEL=0`, matching the game library. MinGW is no
longer used for this plugin build.

CMake discovers the Defold installation (`DETOUR_DEFOLD_DIR`), JNI headers
(`DETOUR_JNI_HOME`, or the installed CLion JBR), and a full Java runtime from
that JDK/JBR (`DETOUR_EDITOR_JAVA`). The latter needs `java.compiler`, which
the trimmed editor runtime does not have. The pinned ECJ 3.43.0 compiler is
downloaded into the ignored build cache when missing (`DETOUR_ECJ_JAR` can
point to an existing copy). It reads the installed Defold API JAR and emits
Java 21 classes. The Java archive contains only the plugin classes, not
ECJ or the editor API. No Java tools or JNI headers are needed by game users.

Targets `navmesh_editor` and `navmesh_editor_java` can be built individually
for development, but `detour_package` publishes the results to `plugins`.
Android presets disable the host plugin build and leave the Windows plugin
artifacts intact. Rebuild the Windows package for editor changes.

### What reaches the game

`plugins/lib/.../navmesh_editor.dll`, `plugins/share/navmesh-editor.jar`, and
`editor/src/navmesh.clj` are editor/build-time artifacts. They are not runtime
dependencies and are not bundled as game resources by this example. In
particular, the native JNI adapter is not part of `recast.lib` or `detour_runtime.lib`.
The Java resource builder is required while compiling `.navmesh` resources;
its output is the `.navmeshc` containing mesh bytes and settings, not Java code.

The native `.navmeshc` resource/component handler under `extensions/detour/source/runtime`
does ship in the custom engine through `detour_runtime.lib` because collections
reference that component. Its runtime loader and GPU renderer have no Java,
Clojure or JNI dependency. The example archive includes `.navmeshc`, render
materials/shaders and the Lua render helper, without the separate source `.bin`.
