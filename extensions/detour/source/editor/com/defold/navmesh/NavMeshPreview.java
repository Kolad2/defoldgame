package com.defold.navmesh;

import java.io.File;

/** Editor bridge to the upstream Detour/DebugUtils libraries. */
public final class NavMeshPreview {
    private static boolean loaded;
    static synchronized void load() {
        if (loaded) return;
        String filename = System.mapLibraryName("navmesh_editor");
        for (String directory : System.getProperty("java.library.path").split(File.pathSeparator)) {
            File library = new File(directory, filename);
            if (library.isFile()) {
                System.load(library.getAbsolutePath());
                loaded = true;
                return;
            }
        }
        throw new IllegalStateException("NavMesh editor library is missing for this host: " + filename +
            ". Build extensions/detour/plugins/lib/<host-platform> and restart Defold.");
    }
    public static float[][] read(byte[] data) { load(); return readNative(data); }
    private static native float[][] readNative(byte[] data);
}
