// Editor JNI adapter. Upstream Detour and DebugUtils are compiled unchanged.
#include <jni.h>
#include <DetourNavMesh.h>
#include <DetourAlloc.h>
#include <DetourDebugDraw.h>
#include <DebugDraw.h>
#include <cstring>
#include <cmath>
#include <memory>
#include <limits>
#include <stdexcept>
#include <vector>

namespace {
void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
struct SetHeader { int magic, version, tiles; dtNavMeshParams params; };
struct TileHeader { dtTileRef ref; int size; };
static_assert(sizeof(SetHeader) == 40 && sizeof(TileHeader) == 8,
              "This reader supports RecastDemo MSET v1 with 32-bit poly references.");

// Validate the serialized arrays before handing data to Detour (which trusts its input).
void validateTile(const unsigned char* data, size_t size) {
    require(size >= sizeof(dtMeshHeader), "Truncated Detour tile header");
    dtMeshHeader h; std::memcpy(&h, data, sizeof(h));
    require(h.magic == DT_NAVMESH_MAGIC && h.version == DT_NAVMESH_VERSION,
            "Expected Detour tile version 7");
    const int counts[] = {h.polyCount, h.vertCount, h.maxLinkCount, h.detailMeshCount,
        h.detailVertCount, h.detailTriCount, h.bvNodeCount, h.offMeshConCount, h.offMeshBase};
    for (int n : counts) require(n >= 0 && n <= 10000000, "Invalid Detour tile count");
    require(h.offMeshBase == h.detailMeshCount && h.offMeshBase + h.offMeshConCount == h.polyCount,
            "Invalid Detour polygon/detail counts");
    size_t pos = sizeof(dtMeshHeader);
    auto section = [&](size_t count, size_t stride) {
        size_t begin = pos; pos += (count * stride + 3) & ~size_t(3);
        require(pos <= size, "Truncated Detour tile arrays"); return begin;
    };
    size_t verts = section(h.vertCount, 3 * sizeof(float));
    size_t polys = section(h.polyCount, sizeof(dtPoly));
    section(h.maxLinkCount, sizeof(dtLink));
    size_t details = section(h.detailMeshCount, sizeof(dtPolyDetail));
    size_t detailVerts = section(h.detailVertCount, 3 * sizeof(float));
    size_t tris = section(h.detailTriCount, 4);
    section(h.bvNodeCount, sizeof(dtBVNode));
    section(h.offMeshConCount, sizeof(dtOffMeshConnection));
    require(pos == size, "Unsupported Detour tile layout (expected 32-bit references)");
    for (int i = 0; i < h.vertCount * 3; ++i) {
        float f; std::memcpy(&f, data + verts + i * 4, 4);
        require(std::isfinite(f), "Non-finite NavMesh vertex");
    }
    for (int i = 0; i < h.detailVertCount * 3; ++i) {
        float f; std::memcpy(&f, data + detailVerts + i * 4, 4);
        require(std::isfinite(f), "Non-finite NavMesh detail vertex");
    }
    for (int i = 0; i < h.polyCount; ++i) {
        dtPoly p; std::memcpy(&p, data + polys + i * sizeof(p), sizeof(p));
        require(p.vertCount >= 2 && p.vertCount <= DT_VERTS_PER_POLYGON, "Invalid polygon vertex count");
        require(p.getType() == (i < h.offMeshBase ? DT_POLYTYPE_GROUND : DT_POLYTYPE_OFFMESH_CONNECTION),
                "Invalid polygon type");
        for (int j = 0; j < p.vertCount; ++j) {
            require(p.verts[j] < h.vertCount, "Invalid polygon vertex index");
            require((p.neis[j] & DT_EXT_LINK) || p.neis[j] <= h.polyCount, "Invalid polygon neighbour");
        }
        if (i >= h.detailMeshCount) continue;
        dtPolyDetail d; std::memcpy(&d, data + details + i * sizeof(d), sizeof(d));
        require(size_t(d.vertBase) + d.vertCount <= size_t(h.detailVertCount) &&
                size_t(d.triBase) + d.triCount <= size_t(h.detailTriCount), "Invalid detail mesh range");
        for (unsigned t = d.triBase; t < d.triBase + d.triCount; ++t)
            for (int j = 0; j < 3; ++j)
                require(data[tris + t * 4 + j] < p.vertCount + d.vertCount, "Invalid detail triangle index");
    }
}

class Draw : public duDebugDraw {
    duDebugDrawPrimitives primitive;
    std::vector<float> batch;
public:
    std::vector<float> triangles, lines;
    void depthMask(bool) override {}
    void texture(bool) override {}
    void begin(duDebugDrawPrimitives p, float = 1) override { primitive = p; batch.clear(); }
    void vertex(const float* p, unsigned int c) override { vertex(p[0], p[1], p[2], c); }
    void vertex(float x, float y, float z, unsigned int) override {
        batch.insert(batch.end(), {x, y, z});
        require(batch.size() <= 30000000, "NavMesh debug geometry is too large");
    }
    void vertex(const float* p, unsigned int c, const float*) override { vertex(p, c); }
    void vertex(float x, float y, float z, unsigned int c, float, float) override { vertex(x, y, z, c); }
    void end() override {
        if (primitive == DU_DRAW_TRIS) {
            triangles.insert(triangles.end(), batch.begin(), batch.end());
            for (size_t i = 0; i + 8 < batch.size(); i += 9)
                for (int j = 0; j < 3; ++j) {
                    size_t a = i + j * 3, b = i + ((j + 1) % 3) * 3;
                    lines.insert(lines.end(), batch.begin() + a, batch.begin() + a + 3);
                    lines.insert(lines.end(), batch.begin() + b, batch.begin() + b + 3);
                }
        } else if (primitive == DU_DRAW_LINES) {
            lines.insert(lines.end(), batch.begin(), batch.end());
        }
        require(lines.size() <= 60000000, "NavMesh debug geometry is too large");
    }
};
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_defold_navmesh_NavMeshPreview_readNative(JNIEnv* env, jclass, jbyteArray input) {
    try {
        const jsize input_length = env->GetArrayLength(input);
        const size_t size = static_cast<size_t>(input_length);
        require(size >= sizeof(SetHeader) && size <= 256 * 1024 * 1024, "Invalid NavMesh file size");
        std::vector<unsigned char> bytes(size);
        env->GetByteArrayRegion(input, 0, input_length, reinterpret_cast<jbyte*>(bytes.data()));
        if (env->ExceptionCheck()) return nullptr;
        SetHeader h; std::memcpy(&h, bytes.data(), sizeof(h));
        require(h.magic == ('M'<<24|'S'<<16|'E'<<8|'T') && h.version == 1,
                "Expected RecastDemo MSET version 1 (navmesh.bin), not a GLB or TileCache file");
        require(h.tiles > 0 && h.tiles <= h.params.maxTiles && h.params.maxTiles <= 65536 &&
                h.params.maxPolys > 0 && h.params.maxPolys <= (1<<22), "Invalid NavMesh capacity");
        require(std::isfinite(h.params.tileWidth) && h.params.tileWidth > 0 &&
                std::isfinite(h.params.tileHeight) && h.params.tileHeight > 0, "Invalid NavMesh tile size");
        std::unique_ptr<dtNavMesh, decltype(&dtFreeNavMesh)> mesh(dtAllocNavMesh(), dtFreeNavMesh);
        require(mesh && dtStatusSucceed(mesh->init(&h.params)), "Cannot initialize Detour NavMesh");
        size_t offset = sizeof(h);
        for (int i = 0; i < h.tiles; ++i) {
            require(offset + sizeof(TileHeader) <= size, "Truncated NavMesh tile header");
            TileHeader t; std::memcpy(&t, bytes.data() + offset, sizeof(t)); offset += sizeof(t);
            require(t.ref && t.size > 0 && size_t(t.size) <= size - offset, "Truncated NavMesh tile");
            validateTile(bytes.data() + offset, t.size);
            unsigned char* data = static_cast<unsigned char*>(dtAlloc(t.size, DT_ALLOC_PERM));
            require(data != nullptr, "Cannot allocate NavMesh tile");
            std::memcpy(data, bytes.data() + offset, t.size); offset += t.size;
            dtStatus status = mesh->addTile(data, t.size, DT_TILE_FREE_DATA, t.ref, nullptr);
            if (dtStatusFailed(status)) { dtFree(data); throw std::runtime_error("Detour rejected NavMesh tile"); }
        }
        require(offset == size, "Unexpected data after NavMesh tiles");
        Draw draw; duDebugDrawNavMesh(&draw, *mesh, DU_DRAWNAVMESH_OFFMESHCONS);
        jclass arrayClass = env->FindClass("[F");
        jobjectArray result = env->NewObjectArray(2, arrayClass, nullptr);
        if (!result) return nullptr;
        const std::vector<float>* arrays[] = {&draw.triangles, &draw.lines};
        for (int i = 0; i < 2; ++i) {
            require(arrays[i]->size() <= static_cast<size_t>(std::numeric_limits<jsize>::max()),
                    "NavMesh debug array is too large for Java");
            const jsize count = static_cast<jsize>(arrays[i]->size());
            jfloatArray values = env->NewFloatArray(count);
            if (!values) return nullptr;
            env->SetFloatArrayRegion(values, 0, count, arrays[i]->data());
            env->SetObjectArrayElement(result, i, values); env->DeleteLocalRef(values);
        }
        return result;
    } catch (const std::exception& e) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"), e.what()); return nullptr;
    }
}
