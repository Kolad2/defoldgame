#include "navmesh_runtime.h"
#include "DebugDraw.h"
#include "DetourDebugDraw.h"
#include <dmsdk/resource/resource.h>
#include <dmsdk/gameobject/component.h>
#include <dmsdk/gamesys/script.h>
#include <dmsdk/gamesys/resources/res_material.h>
#include <dmsdk/dlib/transform.h>
#include <dmsdk/dlib/context_registry.h>
#include <algorithm>
#include <vector>

namespace {
struct Geometry : duDebugDraw {
    std::vector<float> triangles, lines, batch;
    duDebugDrawPrimitives primitive;
    void depthMask(bool) {}
    void texture(bool) {}
    void begin(duDebugDrawPrimitives p,float) { primitive=p; batch.clear(); }
    void vertex(const float* p,unsigned c) { vertex(p[0],p[1],p[2],c); }
    void vertex(const float* p,unsigned c,const float*) { vertex(p,c); }
    void vertex(float x,float y,float z,unsigned c,float,float) { vertex(x,y,z,c); }
    void vertex(float x,float y,float z,unsigned) { batch.push_back(x); batch.push_back(y); batch.push_back(z); }
    void end() {
        if (primitive==DU_DRAW_TRIS) {
            triangles.insert(triangles.end(),batch.begin(),batch.end());
            for (size_t i=0;i+8<batch.size();i+=9) for (int j=0;j<3;++j) {
                size_t a=i+j*3,b=i+((j+1)%3)*3;
                lines.insert(lines.end(),batch.begin()+a,batch.begin()+a+3);
                lines.insert(lines.end(),batch.begin()+b,batch.begin()+b+3);
            }
        } else if (primitive==DU_DRAW_LINES) lines.insert(lines.end(),batch.begin(),batch.end());
    }
};
struct Resource {
    dtNavMesh* mesh;
    DetourExtension::DebugSettings settings;
    dmGameSystem::MaterialResource* materials[2];
    Geometry geometry;
    Resource() : mesh(0) { materials[0]=materials[1]=0; }
};
struct Context {
    dmRender::HRenderContext render;
    dmGraphics::HContext graphics;
    dmGraphics::HVertexDeclaration declaration;
};
struct Component {
    Resource* resource;
    NavMesh* navigation;
    dmGraphics::HVertexBuffer buffers[2];
    dmRender::RenderObject objects[2];
    dmVMath::Matrix4 local_transform;
    bool enabled, added;
};
struct World { std::vector<Component*> components; };

void ReleaseResource(dmResource::HFactory factory,Resource* r) {
    if (!r) return;
    for (int i=0;i<2;++i) if (r->materials[i]) dmResource::Release(factory,r->materials[i]);
    dtFreeNavMesh(r->mesh); delete r;
}
Resource* LoadResource(dmResource::HFactory factory,const void* data,size_t size) {
    Resource* r=new Resource;
    std::string paths[2]; const unsigned char* bytes=0; size_t meshSize=0;
    if (!DetourExtension::ReadCompiled(data,size,r->settings,paths,bytes,meshSize)) {
        dmLogError("Invalid .navmeshc: rebuild resources with the current NavMesh plugin.");
        ReleaseResource(factory,r); return 0;
    }
    std::string error; r->mesh=DetourExtension::LoadMesh(bytes,meshSize,error);
    if (!r->mesh) { dmLogError("NavMesh: %s",error.c_str()); ReleaseResource(factory,r); return 0; }
    for (int i=0;i<2;++i) if (dmResource::Get(factory,paths[i].c_str(),reinterpret_cast<void**>(&r->materials[i]))!=dmResource::RESULT_OK) {
        ReleaseResource(factory,r); return 0;
    }
    duDebugDrawNavMesh(&r->geometry,*r->mesh,DU_DRAWNAVMESH_OFFMESHCONS);
    return r;
}
dmResource::Result PreloadResource(const dmResource::ResourcePreloadParams* p) {
    DetourExtension::DebugSettings settings; std::string paths[2]; const unsigned char* mesh; size_t size;
    if (!DetourExtension::ReadCompiled(p->m_Buffer,p->m_BufferSize,settings,paths,mesh,size)) return dmResource::RESULT_FORMAT_ERROR;
    for (int i=0;i<2;++i) dmResource::PreloadHint(p->m_HintInfo,paths[i].c_str());
    return dmResource::RESULT_OK;
}
dmResource::Result CreateResource(const dmResource::ResourceCreateParams* p) {
    Resource* r=LoadResource(p->m_Factory,p->m_Buffer,p->m_BufferSize);
    if (!r) return dmResource::RESULT_FORMAT_ERROR;
    dmResource::SetResource(p->m_Resource,r); return dmResource::RESULT_OK;
}
dmResource::Result DestroyResource(const dmResource::ResourceDestroyParams* p) {
    ReleaseResource(p->m_Factory,static_cast<Resource*>(dmResource::GetResource(p->m_Resource)));
    return dmResource::RESULT_OK;
}
dmResource::Result RecreateResource(const dmResource::ResourceRecreateParams* p) {
    Resource* replacement=LoadResource(p->m_Factory,p->m_Buffer,p->m_BufferSize);
    if (!replacement) return dmResource::RESULT_FORMAT_ERROR;
    Resource* r=static_cast<Resource*>(dmResource::GetResource(p->m_Resource));
    // Resource address stays stable. OnReload invalidates old navigation handles.
    std::swap(r->mesh,replacement->mesh); std::swap(r->settings,replacement->settings);
    for (int i=0;i<2;++i) std::swap(r->materials[i],replacement->materials[i]);
    r->geometry.triangles.swap(replacement->geometry.triangles); r->geometry.lines.swap(replacement->geometry.lines);
    ReleaseResource(p->m_Factory,replacement); return dmResource::RESULT_OK;
}
ResourceResult RegisterResource(HResourceTypeContext context,HResourceType type) {
    return (ResourceResult)dmResource::SetupType(context,type,0,PreloadResource,CreateResource,0,DestroyResource,RecreateResource);
}
dmGameObject::CreateResult NewWorld(const dmGameObject::ComponentNewWorldParams& p) {
    *p.m_World=new World; return dmGameObject::CREATE_RESULT_OK;
}
dmGameObject::CreateResult DeleteWorld(const dmGameObject::ComponentDeleteWorldParams& p) {
    delete static_cast<World*>(p.m_World); return dmGameObject::CREATE_RESULT_OK;
}
void Upload(Component* c,Context* context) {
    const std::vector<float>* arrays[]={&c->resource->geometry.triangles,&c->resource->geometry.lines};
    for (int i=0;i<2;++i) {
        if (c->buffers[i]) dmGraphics::DeleteVertexBuffer(c->buffers[i]);
        c->buffers[i]=dmGraphics::NewVertexBuffer(context->graphics,(uint32_t)(arrays[i]->size()*sizeof(float)),arrays[i]->data(),dmGraphics::BUFFER_USAGE_STATIC_DRAW);
        dmRender::RenderObject& object=c->objects[i];
        object.m_VertexBuffer=c->buffers[i]; object.m_VertexDeclaration=context->declaration;
        object.m_VertexCount=(uint32_t)(arrays[i]->size()/3);
        object.m_PrimitiveType=i==0 ? dmGraphics::PRIMITIVE_TRIANGLES : dmGraphics::PRIMITIVE_LINES;
        object.m_SetBlendFactors=1; object.m_SourceBlendFactor=dmGraphics::BLEND_FACTOR_ONE;
        object.m_DestinationBlendFactor=dmGraphics::BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        object.m_SourceBlendFactorAlpha=dmGraphics::BLEND_FACTOR_ONE;
        object.m_DestinationBlendFactorAlpha=dmGraphics::BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    }
}
dmGameObject::CreateResult CreateComponent(const dmGameObject::ComponentCreateParams& p) {
    Component* c=new Component; c->resource=static_cast<Resource*>(p.m_Resource);
    c->navigation=CreateNavigation(c->resource->mesh,false);
    if (!c->navigation) { delete c; return dmGameObject::CREATE_RESULT_UNKNOWN_ERROR; }
    c->navigation->game_object=p.m_Instance;
    dmTransform::Transform local;
    local.SetTranslation(dmVMath::Vector3(p.m_Position)); local.SetRotation(p.m_Rotation); local.SetScale(p.m_Scale);
    c->local_transform=dmTransform::ToMatrix4(local);
    c->navigation->local_transform=c->local_transform; c->navigation->settings=&c->resource->settings;
    c->enabled=true; c->added=false;
    for (int i=0;i<2;++i) { c->buffers[i]=0; c->objects[i].m_ConstantBuffer=dmRender::NewNamedConstantBuffer(); }
    Upload(c,static_cast<Context*>(p.m_Context));
    static_cast<World*>(p.m_World)->components.push_back(c); *p.m_UserData=reinterpret_cast<uintptr_t>(c);
    return dmGameObject::CREATE_RESULT_OK;
}
dmGameObject::CreateResult DestroyComponent(const dmGameObject::ComponentDestroyParams& p) {
    Component* c=reinterpret_cast<Component*>(*p.m_UserData); World* world=static_cast<World*>(p.m_World);
    world->components.erase(std::find(world->components.begin(),world->components.end(),c)); DestroyNavigation(c->navigation);
    for (int i=0;i<2;++i) { dmGraphics::DeleteVertexBuffer(c->buffers[i]); dmRender::DeleteNamedConstantBuffer(c->objects[i].m_ConstantBuffer); }
    delete c; return dmGameObject::CREATE_RESULT_OK;
}
dmGameObject::CreateResult AddToUpdate(const dmGameObject::ComponentAddToUpdateParams& p) {
    reinterpret_cast<Component*>(*p.m_UserData)->added=true; return dmGameObject::CREATE_RESULT_OK;
}
void* GetComponent(const dmGameObject::ComponentGetParams& p) { return reinterpret_cast<void*>(p.m_UserData); }
dmGameObject::UpdateResult OnMessage(const dmGameObject::ComponentOnMessageParams& p) {
    Component* c=reinterpret_cast<Component*>(*p.m_UserData);
    if (p.m_Message->m_Id==dmHashString64("enable")) c->enabled=true;
    else if (p.m_Message->m_Id==dmHashString64("disable")) c->enabled=false;
    return dmGameObject::UPDATE_RESULT_OK;
}
void OnReload(const dmGameObject::ComponentOnReloadParams& p) {
    Component* c=reinterpret_cast<Component*>(*p.m_UserData); c->resource=static_cast<Resource*>(p.m_Resource);
    NavMesh* previous=c->navigation; NavMesh* navigation=CreateNavigation(c->resource->mesh,false);
    if (!navigation) { DestroyNavigation(previous); c->navigation=0; return; }
    navigation->game_object=p.m_Instance; navigation->local_transform=c->local_transform;
    navigation->settings=&c->resource->settings; navigation->debug_enabled=previous && previous->debug_enabled;
    DestroyNavigation(previous); c->navigation=navigation; Upload(c,static_cast<Context*>(p.m_Context));
}
void Dispatch(const dmRender::RenderListDispatchParams& p) {
    if (p.m_Operation!=dmRender::RENDER_LIST_OPERATION_BATCH) return;
    for (uint32_t* it=p.m_Begin;it!=p.m_End;++it) dmRender::AddToRender(p.m_Context,reinterpret_cast<dmRender::RenderObject*>(p.m_Buf[*it].m_UserData));
}
dmGameObject::UpdateResult Render(const dmGameObject::ComponentsRenderParams& p) {
    World* world=static_cast<World*>(p.m_World); Context* context=static_cast<Context*>(p.m_Context);
    dmRender::HRenderListDispatch dispatch=dmRender::RenderListMakeDispatch(context->render,Dispatch,0);
    for (Component* c:world->components) {
        if (!c->enabled || !c->added || !c->navigation || !c->navigation->debug_enabled) continue;
        const DetourExtension::DebugSettings& settings=c->resource->settings;
        dmVMath::Matrix4 transform=NavigationTransform(c->navigation)*dmVMath::Matrix4::translation(dmVMath::Vector3(0,settings.offset,0));
        for (int i=0;i<2;++i) {
            if ((i==0 ? !settings.surface : !settings.edges) || !c->objects[i].m_VertexCount) continue;
            dmRender::RenderObject& object=c->objects[i]; object.m_WorldTransform=transform;
            object.m_Material=c->resource->materials[settings.xray ? 1 : 0]->m_Material;
            dmVMath::Vector4 tint(settings.color[0],settings.color[1],settings.color[2],settings.color[3]*(i==0 ? settings.opacity : 1.0f));
            dmRender::SetNamedConstant(object.m_ConstantBuffer,dmHashString64("tint"),&tint,1);
            dmRender::RenderListEntry* entry=dmRender::RenderListAlloc(context->render,1);
            entry->m_WorldPosition=dmVMath::Point3(transform.getTranslation()); entry->m_UserData=reinterpret_cast<uint64_t>(&object);
            entry->m_TagListKey=dmRender::GetMaterialTagListKey(object.m_Material); entry->m_BatchKey=0;
            entry->m_MajorOrder=dmRender::RENDER_ORDER_AFTER_WORLD; entry->m_Order=i; entry->m_MinorOrder=0; entry->m_Dispatch=dispatch;
            dmRender::RenderListSubmit(context->render,entry,entry+1);
        }
    }
    return dmGameObject::UPDATE_RESULT_OK;
}
dmGameObject::Result RegisterComponent(const dmGameObject::ComponentTypeCreateCtx* p,dmGameObject::ComponentType* type) {
    HContextRegistry registry=dmGameObject::ComponentGetContextRegistry(p); Context* context=new Context;
    context->render=static_cast<dmRender::HRenderContext>(ContextRegistryGet(registry,RENDER_CONTEXT_NAME));
    context->graphics=static_cast<dmGraphics::HContext>(ContextRegistryGet(registry,GRAPHICS_CONTEXT_NAME));
    if (!context->render || !context->graphics) { delete context; return dmGameObject::RESULT_UNKNOWN_ERROR; }
    dmGraphics::HVertexStreamDeclaration streams=dmGraphics::NewVertexStreamDeclaration(context->graphics);
    dmGraphics::AddVertexStream(streams,"position",3,dmGraphics::TYPE_FLOAT,false);
    context->declaration=dmGraphics::NewVertexDeclaration(context->graphics,streams); dmGraphics::DeleteVertexStreamDeclaration(streams);
    dmGameObject::ComponentTypeSetContext(type,context); dmGameObject::ComponentTypeSetHasUserData(type,true);
    dmGameObject::ComponentTypeSetReadsTransforms(type,true); dmGameObject::ComponentTypeSetNewWorldFn(type,NewWorld);
    dmGameObject::ComponentTypeSetDeleteWorldFn(type,DeleteWorld); dmGameObject::ComponentTypeSetCreateFn(type,CreateComponent);
    dmGameObject::ComponentTypeSetDestroyFn(type,DestroyComponent); dmGameObject::ComponentTypeSetAddToUpdateFn(type,AddToUpdate);
    dmGameObject::ComponentTypeSetGetFn(type,GetComponent); dmGameObject::ComponentTypeSetOnMessageFn(type,OnMessage);
    dmGameObject::ComponentTypeSetOnReloadFn(type,OnReload); dmGameObject::ComponentTypeSetRenderFn(type,Render);
    return dmGameObject::RESULT_OK;
}
dmGameObject::Result UnregisterComponent(const dmGameObject::ComponentTypeCreateCtx*,dmGameObject::ComponentType* type) {
    Context* context=static_cast<Context*>(dmGameObject::ComponentTypeGetContext(type));
    dmGraphics::DeleteVertexDeclaration(context->declaration); delete context; return dmGameObject::RESULT_OK;
}
}
NavMesh* GetNavigationComponent(lua_State* L,int index) {
    dmGameObject::HComponent handle; dmScript::GetComponentFromLua(L,index,"navmeshc",0,&handle,0);
    NavMesh* navigation=static_cast<Component*>(handle)->navigation;
    if (!navigation) luaL_error(L,"NavMesh query allocation failed after resource reload");
    return navigation;
}
DM_DECLARE_RESOURCE_TYPE(NavMeshPreviewResource,"navmeshc",RegisterResource,0);
DM_DECLARE_COMPONENT_TYPE(NavMeshPreviewComponent,"navmeshc",RegisterComponent,UnregisterComponent);
