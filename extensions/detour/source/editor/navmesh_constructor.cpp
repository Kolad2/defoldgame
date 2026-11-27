// Editor-only Recast baker. Geometry comes from Defold model scene buffers.
#include <jni.h>
#include <Recast.h>
#include <RecastDebugDraw.h>
#include <DetourNavMesh.h>
#include <DetourNavMeshBuilder.h>
#include <DetourNavMeshQuery.h>
#include <DetourDebugDraw.h>
#include <DebugDraw.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
void check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
template<class T, void(*Free)(T*)> using Owned = std::unique_ptr<T, decltype(Free)>;
struct Tile {
    Owned<rcHeightfield, rcFreeHeightField> solid{nullptr,rcFreeHeightField};
    Owned<rcCompactHeightfield,rcFreeCompactHeightfield> compact{nullptr,rcFreeCompactHeightfield};
    Owned<rcContourSet,rcFreeContourSet> contours{nullptr,rcFreeContourSet};
    Owned<rcPolyMesh,rcFreePolyMesh> poly{nullptr,rcFreePolyMesh};
    Owned<rcPolyMeshDetail,rcFreePolyMeshDetail> detail{nullptr,rcFreePolyMeshDetail};
};
struct Session {
    std::vector<float> vertices;
    std::vector<int> indices;
    std::vector<unsigned> colors;
    Owned<dtNavMesh,dtFreeNavMesh> mesh{nullptr,dtFreeNavMesh};
    Owned<dtNavMeshQuery,dtFreeNavMeshQuery> query{nullptr,dtFreeNavMeshQuery};
    std::vector<std::unique_ptr<Tile>> tiles;
};
std::mutex mutex;
std::map<jlong,std::unique_ptr<Session>> sessions;
jlong nextSession=1;
Session& get(jlong id) { auto i=sessions.find(id); check(i!=sessions.end(),"Constructor session is closed"); return *i->second; }

// XYZ + RGBA, matching the preview's vertex format. Quads are triangulated.
struct Draw : duDebugDraw {
    std::vector<float> triangles,lines,batch;
    duDebugDrawPrimitives primitive=DU_DRAW_TRIS;
    void depthMask(bool) override {} void texture(bool) override {}
    void begin(duDebugDrawPrimitives p,float=1) override { primitive=p; batch.clear(); }
    void vertex(const float* p,unsigned c) override { vertex(p[0],p[1],p[2],c); }
    void vertex(float x,float y,float z,unsigned c) override {
        check(batch.size()<14000000,"Preview exceeds two million vertices; increase Cell Size or disable intermediates");
        batch.insert(batch.end(),{x,y,z,(c&255)/255.f,((c>>8)&255)/255.f,((c>>16)&255)/255.f,((c>>24)&255)/255.f});
    }
    void vertex(const float* p,unsigned c,const float*) override { vertex(p,c); }
    void vertex(float x,float y,float z,unsigned c,float,float) override { vertex(x,y,z,c); }
    void end() override {
        if(primitive==DU_DRAW_TRIS) triangles.insert(triangles.end(),batch.begin(),batch.end());
        else if(primitive==DU_DRAW_LINES) lines.insert(lines.end(),batch.begin(),batch.end());
        else if(primitive==DU_DRAW_QUADS) for(size_t i=0;i+27<batch.size();i+=28)
            for(int j : {0,1,2,0,2,3}) triangles.insert(triangles.end(),batch.begin()+i+j*7,batch.begin()+i+j*7+7);
        check(triangles.size()+lines.size()<28000000,"Preview is too large; increase Cell Size or disable intermediates");
    }
};
jobjectArray arrays(JNIEnv* e, const Draw& d) {
    jclass type=e->FindClass("[F"); auto out=e->NewObjectArray(2,type,nullptr);
    const std::vector<float>* v[]={&d.triangles,&d.lines};
    for(int i=0;i<2;i++){auto a=e->NewFloatArray((jsize)v[i]->size()); if(!a)return nullptr;
        e->SetFloatArrayRegion(a,0,(jsize)v[i]->size(),v[i]->data()); e->SetObjectArrayElement(out,i,a); e->DeleteLocalRef(a);}
    return out;
}
std::unique_ptr<Session> load(JNIEnv* e, jfloatArray positions, jintArray indices) {
    check(positions && indices, "Missing model geometry");
    int np=e->GetArrayLength(positions), ni=e->GetArrayLength(indices);
    check(np>0 && np%3==0 && np<=6000000, "Model must contain 1..2000000 XYZ vertices");
    check(ni>0 && ni%3==0 && ni<=6000000, "Model must contain 1..2000000 triangles");
    std::unique_ptr<Session> s(new Session);
    s->vertices.resize(np); s->indices.resize(ni);
    e->GetFloatArrayRegion(positions,0,np,s->vertices.data());
    e->GetIntArrayRegion(indices,0,ni,s->indices.data());
    for(float v:s->vertices)check(std::isfinite(v)&&std::abs(v)<1e7f,"Invalid model coordinate");
    for(int i:s->indices)check(i>=0&&i<np/3,"Model index is out of bounds");
    s->colors.resize(ni/3,duRGBA(175,183,190,255));
    return s;
}
struct Context : rcContext {
    std::string logs;
    void doLog(rcLogCategory,const char* msg,int len) override { logs.append(msg,len); logs+='\n'; }
};
std::vector<unsigned char> bake(Session& s,const double* values,bool keep) {
    for(int i=0;i<15;i++)check(std::isfinite(values[i]),"All bake settings must be finite");
    check(values[0]>=.001&&values[1]>=.001&&values[0]<=10000&&values[1]<=10000,"Cell dimensions must be between .001 and 10000");
    for(int i=2;i<15;i++)check(values[i]>=0&&values[i]<=100000,"Bake setting is outside its supported range");
    for(int i:{2,3,5,6,7,8,10,11,12})check(values[i]==std::floor(values[i]),"Cell counts must be whole numbers");
    check(values[4]<90&&values[5]>=3&&values[5]<=255&&values[6]<=255&&values[7]<=255,"Slope must be <90; height 3..255 cells, climb/radius <=255 cells");
    check(values[12]>=3&&values[12]<=DT_VERTS_PER_POLYGON,"Max vertices per polygon must be 3..6");
    check(values[10]<=1000&&values[11]<=1000&&values[9]<=100,"Region size or simplification error is too large");
    rcConfig base={};base.cs=(float)values[0];base.ch=(float)values[1];base.tileSize=(int)values[2];base.borderSize=(int)values[3];
    base.walkableSlopeAngle=(float)values[4];base.walkableHeight=(int)values[5];base.walkableClimb=(int)values[6];base.walkableRadius=(int)values[7];
    base.maxEdgeLen=(int)values[8];base.maxSimplificationError=(float)values[9];base.minRegionArea=(int)(values[10]*values[10]);
    base.mergeRegionArea=(int)(values[11]*values[11]);base.maxVertsPerPoly=(int)values[12];
    base.detailSampleDist=values[13]<.9?0:base.cs*(float)values[13];base.detailSampleMaxError=base.ch*(float)values[14];
    check(base.tileSize==0||(base.tileSize>=8&&base.tileSize<=1024),"Tile Size must be 0 or 8..1024 cells");
    check(base.borderSize<=512,"Border Size must be <=512 cells");
    float bmin[3],bmax[3];rcCalcBounds(s.vertices.data(),(int)s.vertices.size()/3,bmin,bmax);
    double gx=std::ceil((bmax[0]-bmin[0])/base.cs),gz=std::ceil((bmax[2]-bmin[2])/base.cs);
    check(gx>=1&&gz>=1&&gx<=100000&&gz<=100000&&gx*gz<=16000000,"Raster grid is too large or empty; increase Cell Size");
    check((bmax[1]-bmin[1])/base.ch<RC_SPAN_MAX_HEIGHT,"Vertical voxel range is too large; increase Cell Height");
    int gw,gh;rcCalcGridSize(bmin,bmax,base.cs,&gw,&gh);
    int nx=base.tileSize?(gw+base.tileSize-1)/base.tileSize:1,nz=base.tileSize?(gh+base.tileSize-1)/base.tileSize:1;
    check(nx*nz<=16384,"Too many tiles; increase Tile Size");
    int capacity=1;while(capacity<nx*nz)capacity*=2;
    dtNavMeshParams params={};rcVcopy(params.orig,bmin);
    params.tileWidth=base.tileSize?base.tileSize*base.cs:std::max(base.cs,bmax[0]-bmin[0]);
    params.tileHeight=base.tileSize?base.tileSize*base.cs:std::max(base.cs,bmax[2]-bmin[2]);
    params.maxTiles=capacity;params.maxPolys=(1<<22)/capacity;
    Owned<dtNavMesh,dtFreeNavMesh> mesh(dtAllocNavMesh(),dtFreeNavMesh);
    check(mesh&&dtStatusSucceed(mesh->init(&params)),"Cannot allocate navigation mesh");
    std::vector<std::unique_ptr<Tile>> tiles; Context ctx;
    for(int z=0;z<nz;z++)for(int x=0;x<nx;x++) {
        rcConfig c=base;rcVcopy(c.bmin,bmin);rcVcopy(c.bmax,bmax);
        if(base.tileSize){c.borderSize=std::max(base.borderSize,c.walkableRadius+3);
            c.bmin[0]+=x*params.tileWidth;c.bmin[2]+=z*params.tileHeight;
            c.bmax[0]=c.bmin[0]+params.tileWidth;c.bmax[2]=c.bmin[2]+params.tileHeight;
            c.bmin[0]-=c.borderSize*c.cs;c.bmin[2]-=c.borderSize*c.cs;
            c.bmax[0]+=c.borderSize*c.cs;c.bmax[2]+=c.borderSize*c.cs;
            c.width=c.height=c.tileSize+2*c.borderSize;
        }else{c.width=gw;c.height=gh;check(c.borderSize*2<std::min(gw,gh),"Border Size removes the entire mesh");}
        check((long long)c.width*c.height<=4000000,"One tile is too large; use smaller tiles or increase Cell Size");
        std::vector<int> tris;
        for(size_t i=0;i<s.indices.size();i+=3){const float* a=&s.vertices[s.indices[i]*3];const float* b=&s.vertices[s.indices[i+1]*3];const float* d=&s.vertices[s.indices[i+2]*3];
            if(std::max({a[0],b[0],d[0]})<c.bmin[0]||std::min({a[0],b[0],d[0]})>c.bmax[0]||std::max({a[2],b[2],d[2]})<c.bmin[2]||std::min({a[2],b[2],d[2]})>c.bmax[2])continue;
            tris.insert(tris.end(),s.indices.begin()+i,s.indices.begin()+i+3);}
        if(tris.empty())continue;
        std::unique_ptr<Tile> t(new Tile);t->solid.reset(rcAllocHeightfield());t->compact.reset(rcAllocCompactHeightfield());
        t->contours.reset(rcAllocContourSet());t->poly.reset(rcAllocPolyMesh());t->detail.reset(rcAllocPolyMeshDetail());
        check(t->solid&&t->compact&&t->contours&&t->poly&&t->detail,"Cannot allocate Recast intermediates");
        check(rcCreateHeightfield(&ctx,*t->solid,c.width,c.height,c.bmin,c.bmax,c.cs,c.ch),"Cannot create heightfield");
        std::vector<unsigned char> areas(tris.size()/3,0);
        rcMarkWalkableTriangles(&ctx,c.walkableSlopeAngle,s.vertices.data(),(int)s.vertices.size()/3,tris.data(),(int)areas.size(),areas.data());
        check(rcRasterizeTriangles(&ctx,s.vertices.data(),(int)s.vertices.size()/3,tris.data(),areas.data(),(int)areas.size(),*t->solid,c.walkableClimb),"Cannot rasterize GLB");
        rcFilterLowHangingWalkableObstacles(&ctx,c.walkableClimb,*t->solid);rcFilterLedgeSpans(&ctx,c.walkableHeight,c.walkableClimb,*t->solid);
        rcFilterWalkableLowHeightSpans(&ctx,c.walkableHeight,*t->solid);
        check(rcBuildCompactHeightfield(&ctx,c.walkableHeight,c.walkableClimb,*t->solid,*t->compact),"Cannot build compact heightfield");
        check(rcErodeWalkableArea(&ctx,c.walkableRadius,*t->compact),"Cannot erode walkable area");
        check(rcBuildDistanceField(&ctx,*t->compact)&&rcBuildRegions(&ctx,*t->compact,c.borderSize,c.minRegionArea,c.mergeRegionArea),"Cannot build regions");
        check(rcBuildContours(&ctx,*t->compact,c.maxSimplificationError,c.maxEdgeLen,*t->contours),"Cannot build contours");
        check(rcBuildPolyMesh(&ctx,*t->contours,c.maxVertsPerPoly,*t->poly),"Cannot build polygons");
        if(!t->poly->npolys){if(keep)tiles.push_back(std::move(t));continue;}
        check(t->poly->nverts<65535&&t->poly->npolys<=params.maxPolys,"Tile exceeds Detour capacity; reduce Tile Size");
        check(rcBuildPolyMeshDetail(&ctx,*t->poly,*t->compact,c.detailSampleDist,c.detailSampleMaxError,*t->detail),"Cannot build detail mesh");
        for(int i=0;i<t->poly->npolys;i++){t->poly->areas[i]=0;t->poly->flags[i]=1;}
        dtNavMeshCreateParams p={};p.verts=t->poly->verts;p.vertCount=t->poly->nverts;p.polys=t->poly->polys;
        p.polyAreas=t->poly->areas;p.polyFlags=t->poly->flags;p.polyCount=t->poly->npolys;p.nvp=t->poly->nvp;
        p.detailMeshes=t->detail->meshes;p.detailVerts=t->detail->verts;p.detailVertsCount=t->detail->nverts;
        p.detailTris=t->detail->tris;p.detailTriCount=t->detail->ntris;p.walkableHeight=c.walkableHeight*c.ch;
        p.walkableRadius=c.walkableRadius*c.cs;p.walkableClimb=c.walkableClimb*c.ch;p.tileX=x;p.tileY=z;
        rcVcopy(p.bmin,t->poly->bmin);rcVcopy(p.bmax,t->poly->bmax);p.cs=c.cs;p.ch=c.ch;p.buildBvTree=true;
        unsigned char* bytes=nullptr;int size=0;check(dtCreateNavMeshData(&p,&bytes,&size),"Cannot create Detour tile");
        if(dtStatusFailed(mesh->addTile(bytes,size,DT_TILE_FREE_DATA,0,nullptr))){dtFree(bytes);throw std::runtime_error("Cannot add Detour tile");}
        if(keep)tiles.push_back(std::move(t));
    }
    struct Header{int magic,version,count;dtNavMeshParams params;};struct TileHeader{dtTileRef ref;int size;};
    static_assert(sizeof(Header)==40&&sizeof(TileHeader)==8,"MSET v1 requires 32-bit references");
    Header header={0x4d534554,1,0,*mesh->getParams()};
    std::vector<unsigned char> result(sizeof(header));
    for(int i=0;i<mesh->getMaxTiles();i++){const dtMeshTile* t=static_cast<const dtNavMesh*>(mesh.get())->getTile(i);if(!t->header)continue;
        header.count++;TileHeader th={mesh->getTileRef(t),t->dataSize};const auto* h=(const unsigned char*)&th;
        result.insert(result.end(),h,h+sizeof(th));result.insert(result.end(),t->data,t->data+t->dataSize);}
    check(header.count>0,"No walkable polygons. Check mesh winding, agent dimensions and Min Region Area");
    std::memcpy(result.data(),&header,sizeof(header));
    s.query.reset(dtAllocNavMeshQuery());
    check(s.query&&dtStatusSucceed(s.query->init(mesh.get(),4096)),"Cannot create preview query");
    s.mesh=std::move(mesh);s.tiles=std::move(tiles);return result;
}
void draw(Session& s,int mode,Draw& d) {
    if(mode==0){d.begin(DU_DRAW_TRIS);for(size_t i=0;i<s.indices.size();i++)d.vertex(&s.vertices[s.indices[i]*3],s.colors[i/3]);d.end();return;}
    check(s.mesh!=nullptr,"Bake the navigation mesh first");
    if(mode==1){duDebugDrawNavMesh(&d,*s.mesh,DU_DRAWNAVMESH_OFFMESHCONS);return;}
    if(mode==2){duDebugDrawNavMeshBVTree(&d,*s.mesh);return;}
    check(!s.tiles.empty(),"Enable Keep Intermediates and bake again");
    for(auto& t:s.tiles)switch(mode){
        case 3:duDebugDrawHeightfieldSolid(&d,*t->solid);break;
        case 4:duDebugDrawHeightfieldWalkable(&d,*t->solid);break;
        case 5:duDebugDrawCompactHeightfieldSolid(&d,*t->compact);break;
        case 6:duDebugDrawCompactHeightfieldRegions(&d,*t->compact);break;
        case 7:duDebugDrawCompactHeightfieldDistance(&d,*t->compact);break;
        case 8:duDebugDrawRawContours(&d,*t->contours);break;
        case 9:duDebugDrawContours(&d,*t->contours);break;
        case 10:duDebugDrawPolyMesh(&d,*t->poly);break;
        case 11:if(t->detail->nmeshes)duDebugDrawPolyMeshDetail(&d,*t->detail);break;
        default:throw std::runtime_error("Unknown preview mode");
    }
}
void error(JNIEnv* e,const std::exception& ex){e->ThrowNew(e->FindClass("java/lang/IllegalArgumentException"),ex.what());}
}
extern "C" JNIEXPORT jlong JNICALL Java_com_defold_navmesh_NavMeshConstructor_createNative(JNIEnv* e,jclass,jfloatArray positions,jintArray indices){
    try{auto s=load(e,positions,indices);std::lock_guard<std::mutex> lock(mutex);jlong id=nextSession++;sessions[id]=std::move(s);return id;}catch(const std::exception& x){error(e,x);return 0;}}
extern "C" JNIEXPORT void JNICALL Java_com_defold_navmesh_NavMeshConstructor_closeNative(JNIEnv*,jclass,jlong id){std::lock_guard<std::mutex> lock(mutex);sessions.erase(id);}
extern "C" JNIEXPORT jbyteArray JNICALL Java_com_defold_navmesh_NavMeshConstructor_bakeNative(JNIEnv* e,jclass,jlong id,jdoubleArray a,jboolean keep){
    try{check(a&&e->GetArrayLength(a)==15,"Expected 15 bake settings");double v[15];e->GetDoubleArrayRegion(a,0,15,v);
        std::lock_guard<std::mutex> lock(mutex);auto bytes=bake(get(id),v,keep);auto out=e->NewByteArray((jsize)bytes.size());if(out)e->SetByteArrayRegion(out,0,(jsize)bytes.size(),(jbyte*)bytes.data());return out;
    }catch(const std::exception& x){error(e,x);return nullptr;}}
extern "C" JNIEXPORT jobjectArray JNICALL Java_com_defold_navmesh_NavMeshConstructor_geometryNative(JNIEnv* e,jclass,jlong id,jint mode){
    try{std::lock_guard<std::mutex> lock(mutex);Draw d;draw(get(id),mode,d);return arrays(e,d);}catch(const std::exception& x){error(e,x);return nullptr;}}
