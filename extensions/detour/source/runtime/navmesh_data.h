#ifndef DETOUR_NAVMESH_DATA_H
#define DETOUR_NAVMESH_DATA_H
#include "DetourNavMesh.h"
#include "DetourAlloc.h"
#include <cmath>
#include <cstring>
#include <memory>
#include <string>

namespace DetourExtension {
struct DebugSettings {
    float color[4];
    float opacity, offset;
    bool surface, edges, xray;
    DebugSettings() : opacity(.22f), offset(.03f), surface(true), edges(true), xray(false) {
        color[0]=0; color[1]=.75f; color[2]=.95f; color[3]=1;
    }
};
struct CompiledHeader {
    char magic[4];
    unsigned version, flags;
    float color[4], opacity, offset;
    unsigned pathsSize, meshSize;
};
static_assert(sizeof(CompiledHeader) == 44, "NavMesh resource header layout");

inline bool ReadCompiled(const void* input, size_t size, DebugSettings& settings,
                         std::string materials[2], const unsigned char*& mesh, size_t& meshSize) {
    if (size < sizeof(CompiledHeader)) return false;
    CompiledHeader h; std::memcpy(&h, input, sizeof(h));
    if (std::memcmp(h.magic, "NVM2", 4) || h.version != 2 || (h.flags & ~7u) ||
        h.pathsSize < 4 || h.pathsSize > 4096 || h.pathsSize > size-sizeof(h) ||
        h.meshSize != size-sizeof(h)-h.pathsSize || h.meshSize > 256*1024*1024) return false;
    for (int i=0; i<4; ++i) {
        if (!std::isfinite(h.color[i]) || h.color[i]<0 || h.color[i]>1) return false;
        settings.color[i]=h.color[i];
    }
    if (!std::isfinite(h.opacity) || h.opacity<0 || h.opacity>1 || !std::isfinite(h.offset)) return false;
    settings.opacity=h.opacity; settings.offset=h.offset;
    settings.surface=(h.flags&1)!=0; settings.edges=(h.flags&2)!=0; settings.xray=(h.flags&4)!=0;
    const char* path=static_cast<const char*>(input)+sizeof(h);
    size_t remaining=h.pathsSize;
    for (int i=0; i<2; ++i) {
        const char* end=static_cast<const char*>(std::memchr(path, 0, remaining));
        if (!end || path==end || *path!='/') return false;
        materials[i].assign(path, end);
        if (materials[i].size()<10 || materials[i].substr(materials[i].size()-10)!=".materialc") return false;
        remaining-=size_t(end-path)+1; path=end+1;
    }
    if (remaining) return false;
    mesh=reinterpret_cast<const unsigned char*>(path); meshSize=h.meshSize;
    return true;
}

inline bool ValidateTile(const unsigned char* data, size_t size) {
    if (size<sizeof(dtMeshHeader)) return false;
    dtMeshHeader h; std::memcpy(&h, data, sizeof(h));
    if (h.magic!=DT_NAVMESH_MAGIC || h.version!=DT_NAVMESH_VERSION) return false;
    const int counts[]={h.polyCount,h.vertCount,h.maxLinkCount,h.detailMeshCount,
        h.detailVertCount,h.detailTriCount,h.bvNodeCount,h.offMeshConCount,h.offMeshBase};
    for (int count:counts) if (count<0 || count>10000000) return false;
    if (h.offMeshBase!=h.detailMeshCount || h.offMeshBase+h.offMeshConCount!=h.polyCount) return false;
    size_t pos=sizeof(h);
    auto section=[&](size_t count,size_t stride) { size_t start=pos; pos+=(count*stride+3)&~size_t(3); return start; };
    size_t verts=section(h.vertCount,12), polys=section(h.polyCount,sizeof(dtPoly));
    section(h.maxLinkCount,sizeof(dtLink));
    size_t details=section(h.detailMeshCount,sizeof(dtPolyDetail));
    size_t detailVerts=section(h.detailVertCount,12), tris=section(h.detailTriCount,4);
    section(h.bvNodeCount,sizeof(dtBVNode)); section(h.offMeshConCount,sizeof(dtOffMeshConnection));
    if (pos!=size) return false;
    for (int i=0;i<h.vertCount*3;++i) {
        float f; std::memcpy(&f,data+verts+i*4,4); if (!std::isfinite(f)) return false;
    }
    for (int i=0;i<h.detailVertCount*3;++i) {
        float f; std::memcpy(&f,data+detailVerts+i*4,4); if (!std::isfinite(f)) return false;
    }
    for (int i=0;i<h.polyCount;++i) {
        dtPoly p; std::memcpy(&p,data+polys+i*sizeof(p),sizeof(p));
        if (p.vertCount<2 || p.vertCount>DT_VERTS_PER_POLYGON ||
            p.getType()!=(i<h.offMeshBase ? DT_POLYTYPE_GROUND : DT_POLYTYPE_OFFMESH_CONNECTION)) return false;
        for (int j=0;j<p.vertCount;++j)
            if (p.verts[j]>=h.vertCount || (!(p.neis[j]&DT_EXT_LINK) && p.neis[j]>h.polyCount)) return false;
        if (i>=h.detailMeshCount) continue;
        dtPolyDetail d; std::memcpy(&d,data+details+i*sizeof(d),sizeof(d));
        if (size_t(d.vertBase)+d.vertCount>size_t(h.detailVertCount) ||
            size_t(d.triBase)+d.triCount>size_t(h.detailTriCount)) return false;
        for (unsigned t=d.triBase;t<d.triBase+d.triCount;++t)
            for (int j=0;j<3;++j) if (data[tris+t*4+j]>=p.vertCount+d.vertCount) return false;
    }
    return true;
}

inline dtNavMesh* LoadMesh(const void* input, size_t size, std::string& error) {
    struct SetHeader { int magic,version,tiles; dtNavMeshParams params; };
    struct TileHeader { dtTileRef ref; int size; };
    static_assert(sizeof(SetHeader)==40 && sizeof(TileHeader)==8, "MSET v1, 32-bit references required");
    auto fail=[&](const char* message)->dtNavMesh* { error=message; return 0; };
    if (size<sizeof(SetHeader) || size>256*1024*1024) return fail("Invalid MSET size");
    const unsigned char* bytes=static_cast<const unsigned char*>(input);
    SetHeader h; std::memcpy(&h,bytes,sizeof(h));
    if (h.magic!=0x4d534554 || h.version!=1) return fail("Expected RecastDemo MSET v1");
    if (h.tiles<=0 || h.tiles>h.params.maxTiles || h.params.maxTiles>65536 ||
        h.params.maxPolys<=0 || h.params.maxPolys>(1<<22)) return fail("Invalid NavMesh capacity");
    if (!std::isfinite(h.params.tileWidth) || h.params.tileWidth<=0 ||
        !std::isfinite(h.params.tileHeight) || h.params.tileHeight<=0) return fail("Invalid tile size");
    for (int i=0;i<3;++i) if (!std::isfinite(h.params.orig[i])) return fail("Invalid NavMesh origin");
    std::unique_ptr<dtNavMesh,decltype(&dtFreeNavMesh)> mesh(dtAllocNavMesh(),dtFreeNavMesh);
    if (!mesh || dtStatusFailed(mesh->init(&h.params))) return fail("Cannot initialize NavMesh");
    size_t offset=sizeof(h);
    for (int i=0;i<h.tiles;++i) {
        if (sizeof(TileHeader)>size-offset) return fail("Truncated tile header");
        TileHeader tile; std::memcpy(&tile,bytes+offset,sizeof(tile)); offset+=sizeof(tile);
        if (!tile.ref || tile.size<=0 || size_t(tile.size)>size-offset) return fail("Truncated tile");
        if (!ValidateTile(bytes+offset,tile.size)) return fail("Invalid Detour tile arrays");
        unsigned char* data=static_cast<unsigned char*>(dtAlloc(tile.size,DT_ALLOC_PERM));
        if (!data) return fail("Cannot allocate tile");
        std::memcpy(data,bytes+offset,tile.size); offset+=tile.size;
        if (dtStatusFailed(mesh->addTile(data,tile.size,DT_TILE_FREE_DATA,tile.ref,0))) {
            dtFree(data); return fail("Detour rejected tile");
        }
    }
    if (offset!=size) return fail("Unexpected data after NavMesh tiles");
    return mesh.release();
}
}
#endif
