#ifndef DETOUR_NAVMESH_RUNTIME_H
#define DETOUR_NAVMESH_RUNTIME_H
#include <dmsdk/sdk.h>
#include "DetourNavMeshQuery.h"
#include "DetourCrowd.h"
#include "navmesh_data.h"

struct NavMesh {
    dtNavMesh* mesh;
    dtNavMeshQuery* query;
    dtQueryFilter* filter;
    dtCrowd* crowd;
    dmGameObject::HInstance game_object;
    dmVMath::Matrix4 local_transform;
    DetourExtension::DebugSettings* settings;
    unsigned id;
    bool owns_mesh, debug_enabled;
};
NavMesh* CreateNavigation(dtNavMesh* mesh, bool owns_mesh);
void DestroyNavigation(NavMesh* mesh);
int PushNavigation(lua_State* L, NavMesh* mesh);
NavMesh* GetNavigationComponent(lua_State* L, int index);
dmVMath::Matrix4 NavigationTransform(const NavMesh* mesh);
#endif
