#include <dmsdk/sdk.h>
#include "DebugDraw.h"
#include "DetourDebugDraw.h"
#include "navmesh_debug.h"
#include "navmesh_runtime.h"

namespace {
// The upstream renderer emits filled triangles and boundary lines. Display the
// triangles as a cyan wireframe, retaining its separate polygon boundaries and
// off-mesh connection arcs. All coordinates come from the live dtNavMesh.
class LuaDebugDraw : public duDebugDraw {
public:
    LuaDebugDraw(lua_State* L, float offset, NavMesh* navigation)
        : m_L(L), m_Offset(offset), m_Primitive(DU_DRAW_LINES), m_Count(0), m_Lines(0) {
        m_Navigation = navigation;
        m_Transform = navigation ? NavigationTransform(navigation) : dmVMath::Matrix4::identity();
        lua_newtable(L);
        m_Table = lua_gettop(L);
    }

    void depthMask(bool) {}
    void texture(bool) {}
    void begin(duDebugDrawPrimitives primitive, float) {
        m_Primitive = primitive;
        m_Count = 0;
    }
    void end() { m_Count = 0; }

    void vertex(const float* pos, unsigned int color) { vertex(pos[0], pos[1], pos[2], color); }
    void vertex(const float* pos, unsigned int color, const float*) { vertex(pos, color); }
    void vertex(float x, float y, float z, unsigned int color, float, float) { vertex(x, y, z, color); }
    void vertex(float x, float y, float z, unsigned int color) {
        if (m_Primitive == DU_DRAW_POINTS) return;
        m_Vertices[m_Count] = (m_Transform * dmVMath::Point3(x, y + m_Offset, z)).getXYZ();
        m_Colors[m_Count++] = color;
        const int needed = m_Primitive == DU_DRAW_LINES ? 2 : m_Primitive == DU_DRAW_TRIS ? 3 : 4;
        if (m_Count != needed) return;
        if (m_Primitive == DU_DRAW_LINES) {
            // Original boundary alpha can be very low; keep lines legible over
            // the sample level without modifying the upstream debug renderer.
            addLine(0, 1, m_Colors[0] | 0xff000000u);
        } else {
            const unsigned int wireColor = duRGBA(0, 180, 220, 210);
            for (int i = 0; i < needed; ++i) addLine(i, (i + 1) % needed, wireColor);
        }
        m_Count = 0;
    }

private:
    void addLine(int a, int b, unsigned int color) {
        lua_createtable(m_L, 0, 3);
        dmScript::PushVector3(m_L, m_Vertices[a]);
        lua_setfield(m_L, -2, "start_point");
        dmScript::PushVector3(m_L, m_Vertices[b]);
        lua_setfield(m_L, -2, "end_point");
        const DetourExtension::DebugSettings* settings = m_Navigation ? m_Navigation->settings : 0;
        dmVMath::Vector4 rgba = settings ? dmVMath::Vector4(settings->color[0], settings->color[1], settings->color[2], settings->color[3]) : dmVMath::Vector4(
            (color & 255) / 255.0f, ((color >> 8) & 255) / 255.0f,
            ((color >> 16) & 255) / 255.0f, ((color >> 24) & 255) / 255.0f);
        dmScript::PushVector4(m_L, rgba);
        lua_setfield(m_L, -2, "color");
        lua_rawseti(m_L, m_Table, ++m_Lines);
    }

    lua_State* m_L;
    NavMesh* m_Navigation;
    dmVMath::Matrix4 m_Transform;
    float m_Offset;
    duDebugDrawPrimitives m_Primitive;
    int m_Count;
    int m_Lines;
    int m_Table;
    dmVMath::Vector3 m_Vertices[4];
    unsigned int m_Colors[4];
};
}

int PushNavMeshDebugLines(lua_State* L, const dtNavMesh& mesh, unsigned char flags, float offset, NavMesh* navigation) {
    if (navigation && navigation->settings && !navigation->settings->edges) { lua_newtable(L); return 1; }
    LuaDebugDraw draw(L, offset, navigation);
    duDebugDrawNavMesh(&draw, mesh, flags);
    return 1;
}
