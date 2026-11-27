package com.defold.navmesh;

import com.google.protobuf.ByteString;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.HashMap;
import java.util.Map;

/** Editor-only Recast adapter. Defold supplies the selected model's geometry. */
public final class NavMeshConstructor implements AutoCloseable {
    private long handle;

    public NavMeshConstructor(float[] positions, int[] indices) {
        NavMeshPreview.load();
        handle = createNative(positions, indices);
    }
    public synchronized byte[] bake(double[] settings, boolean intermediates) {
        return bakeNative(handle, settings, intermediates);
    }
    public synchronized float[][] geometry(int mode) { return geometryNative(handle, mode); }
    @Override public synchronized void close() {
        if (handle != 0) { closeNative(handle); handle = 0; }
    }

    /** No native state survives evaluation of a cached editor graph output. */
    public static Map<String, Object> preview(float[] positions, int[] indices, double[] settings, int mode) {
        try (NavMeshConstructor constructor = new NavMeshConstructor(positions, indices)) {
            Map<String, Object> result = new HashMap<>();
            result.put("bytes", constructor.bake(settings, mode >= 3));
            float[][] geometry;
            try { geometry = constructor.geometry(mode); }
            catch (IllegalArgumentException error) {
                // Dense intermediate geometry can exceed the preview limit even
                // when the actual navigation mesh is valid and can be saved.
                result.put("warning", error.getMessage());
                geometry = constructor.geometry(1);
            }
            result.put("triangles", geometry[0]);
            result.put("lines", geometry[1]);
            return result;
        }
    }

    // Defold requires a known runtime component type in a .go. This empty Lua
    // module has no callbacks, model dependency or editor/baking implementation.
    public static byte[] marker() {
        return com.dynamo.lua.proto.Lua.LuaModule.newBuilder().setSource(
            com.dynamo.script.proto.Lua.LuaSource.newBuilder()
                .setFilename("@navmeshconstructor")
                .setScript(ByteString.copyFromUtf8("-- NavMeshConstructor: editor authoring only\n")))
            .build().toByteArray();
    }

    public static void saveBin(String projectRoot, String output, byte[] mesh) throws Exception {
        if (mesh == null || mesh.length < 40) throw new IllegalArgumentException("Bake a valid mesh first");
        if (!output.startsWith("/") || !output.toLowerCase(java.util.Locale.ROOT).endsWith(".bin"))
            throw new IllegalArgumentException("Output must be a project path, for example /assets/level.bin");
        Path root = Path.of(projectRoot).toRealPath();
        Path path = root.resolve(output.substring(1)).normalize();
        if (!path.startsWith(root) || path.equals(root)) throw new IllegalArgumentException("Output is outside the project");
        Path existing = path;
        while (!Files.exists(existing)) existing = existing.getParent();
        if (!existing.toRealPath().startsWith(root)) throw new IllegalArgumentException("Output resolves outside the project");
        Files.createDirectories(path.getParent());
        Path temporary = Files.createTempFile(path.getParent(), ".navmesh-write-", ".part");
        try {
            Files.write(temporary, mesh);
            try { Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE); }
            catch (java.nio.file.AtomicMoveNotSupportedException error) {
                Files.move(temporary, path, StandardCopyOption.REPLACE_EXISTING);
            }
        } finally { Files.deleteIfExists(temporary); }
    }

    private static native long createNative(float[] positions, int[] indices);
    private static native void closeNative(long handle);
    private static native byte[] bakeNative(long handle, double[] settings, boolean intermediates);
    private static native float[][] geometryNative(long handle, int mode);
}
