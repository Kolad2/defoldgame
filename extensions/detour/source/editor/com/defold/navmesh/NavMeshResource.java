package com.defold.navmesh;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

/** Shared binary writer for the editor and Bob. All mesh data is embedded. */
public final class NavMeshResource {
    public static byte[] compile(byte[] config, byte[] mesh, String material, String xrayMaterial) throws Exception {
        JsonNode root = new ObjectMapper().readTree(config);
        if (root == null || !root.isObject()) throw new IllegalArgumentException("Expected NavMesh JSON object");
        ByteBuffer source = ByteBuffer.wrap(mesh).order(ByteOrder.LITTLE_ENDIAN);
        if (mesh.length < 40 || mesh.length > 256 * 1024 * 1024 || source.getInt() != 0x4d534554 || source.getInt() != 1)
            throw new IllegalArgumentException("Expected RecastDemo MSET v1 NavMesh");
        float[] color = {0, .75f, .95f, 1};
        JsonNode rgba = root.get("color");
        if (rgba != null) {
            if (!rgba.isArray() || rgba.size() != 4) throw new IllegalArgumentException("Color must have four values");
            for (int i = 0; i < 4; i++) color[i] = unit(rgba.get(i), "Color");
        }
        float opacity = root.has("surface-opacity") ? unit(root.get("surface-opacity"), "Surface Opacity") : .22f;
        float offset = (float) root.path("height-offset").asDouble(.03);
        if (!Float.isFinite(offset)) throw new IllegalArgumentException("Height Offset must be finite");
        int flags = (root.path("show-surface").asBoolean(true) ? 1 : 0)
                  | (root.path("show-edges").asBoolean(true) ? 2 : 0)
                  | (root.path("x-ray").asBoolean(false) ? 4 : 0);
        byte[] paths = (material + "\0" + xrayMaterial + "\0").getBytes(StandardCharsets.UTF_8);
        ByteBuffer out = ByteBuffer.allocate(44 + paths.length + mesh.length).order(ByteOrder.LITTLE_ENDIAN);
        out.put(new byte[]{'N','V','M','2'}).putInt(2).putInt(flags);
        for (float value : color) out.putFloat(value);
        out.putFloat(opacity).putFloat(offset).putInt(paths.length).putInt(mesh.length);
        return out.put(paths).put(mesh).array();
    }

    private static float unit(JsonNode value, String name) {
        float number = (float) value.asDouble(Double.NaN);
        if (!Float.isFinite(number) || number < 0 || number > 1)
            throw new IllegalArgumentException(name + " must be between 0 and 1");
        return number;
    }
}
