-- Run with Defold's bundled luajit-64.exe from the project root.
package.path = "./?.lua;" .. package.path

local vector_mt = {}
vmath = {}
function vmath.vector3(x, y, z)
    return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vector_mt)
end
function vmath.vector4(x, y, z, w) return {x = x, y = y, z = z, w = w} end
function vector_mt.__unm(v) return vmath.vector3(-v.x, -v.y, -v.z) end
function vmath.length_sqr(v) return v.x * v.x + v.y * v.y + v.z * v.z end
function vmath.normalize(v)
    local n = math.sqrt(vmath.length_sqr(v))
    return vmath.vector3(v.x / n, v.y / n, v.z / n)
end
function vmath.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

-- Only the Defold API boundary is stubbed; visibility uses a small room fixture.
hash = function(value) return value end
msg = {url = function(_, id, component) return id .. "#" .. component end}
local transforms, visible, changes = {}, {}, 0
local mesh_bounds = {floor = {}, area = {}}
go = {
    update_world_transform = function() end,
    get_world_transform = function(id) return transforms[id] or 0 end,
}
function vmath.inv(angle)
    return setmetatable({}, {__mul = function(_, v)
        local c, s = math.cos(angle), math.sin(angle)
        return vmath.vector4(c * v.x - s * v.z, v.y, s * v.x + c * v.z, v.w)
    end})
end
model = {
    get_mesh_aabb = function(url)
        visible[url] = visible[url] or {}
        for mesh in pairs(mesh_bounds) do
            if visible[url][mesh] == nil then visible[url][mesh] = true end
        end
        return mesh_bounds
    end,
    get_mesh_enabled = function(url, mesh)
        visible[url] = visible[url] or {}
        if visible[url][mesh] == nil then visible[url][mesh] = true end
        return visible[url][mesh]
    end,
    set_mesh_enabled = function(url, mesh, enabled)
        visible[url][mesh] = enabled
        changes = changes + 1
    end,
}

local Location = require("scripts.location.location")
local Wall = require("scripts.location.wall")
local wall_nodes = {}
local scene = {{room = {"floor", {walls = wall_nodes}, {doors = {{door_1 = {"area"}}}}}}}
local function group(name, meshes)
    wall_nodes[#wall_nodes + 1] = {[name] = meshes}
    for _, mesh in ipairs(meshes) do mesh_bounds[mesh] = {} end
end
for _, name in ipairs({"down", "right", "top", "left"}) do
    group("wall_" .. name, {"wall_" .. name, "beam_" .. name .. "_top"})
end
for _, name in ipairs({"down_left", "down_right", "top_left", "top_right"}) do
    group("wall_" .. name, {"corner_" .. name})
end
wall_nodes[1].wall_down[#wall_nodes[1].wall_down + 1] = {details = {"extra_beam", "empty_marker"}}
mesh_bounds.extra_beam = {}

local location = Location:create("bar", scene)
local count = 0
for _ in pairs(location.walls) do count = count + 1 end
assert(count == 8, "Exactly eight wall groups")
assert(#location.walls.wall_down.meshes == 3, "Nested meshes included, empty nodes skipped, names deduplicated")
for _, wall in pairs(location.walls) do
    assert(getmetatable(wall) == Wall, "Each wall group is a Wall instance")
    assert(wall.id == "bar" and wall.model_url == "bar#room", "Wall addresses the location model")
end
assert(location.walls.floor == nil, "Only wall groups belong to the dictionary")
for key in pairs(location) do
    assert(key == "id" or key == "model_url" or key == "walls", "Unexpected retained state: " .. key)
end
local state = visible["bar#room"]
local function check(name, expected) assert(state[name] == expected, name) end
local function check_corners(s)
    s = s or state
    assert(s.corner_down_left == (s.wall_down or s.wall_left), "down-left corner")
    assert(s.corner_down_right == (s.wall_down or s.wall_right), "down-right corner")
    assert(s.corner_top_left == (s.wall_top or s.wall_left), "top-left corner")
    assert(s.corner_top_right == (s.wall_top or s.wall_right), "top-right corner")
end

location:set_node_visible("area", false)
for _, direction in ipairs({{-1, -1, -1}, {1, -1, -1}, {1, -1, 1}, {-1, -1, 1}}) do
    location:update_visibility(vmath.vector3(direction[1], direction[2], direction[3]))
    check("wall_down", direction[3] > 0)
    check("wall_top", direction[3] < 0)
    check("wall_right", direction[1] > 0)
    check("wall_left", direction[1] < 0)
    for _, side in ipairs({"down", "right", "top", "left"}) do
        assert(state["beam_" .. side .. "_top"] == state["wall_" .. side])
    end
    check_corners()
    check("extra_beam", state.wall_down)
    check("floor", true)
    check("area", false)
end

-- Manual operations affect only the requested meshes, without remembered masks.
location:update_visibility(vmath.vector3(-1, -1, -1))
location.walls.wall_left:set_visible(false)
check("wall_left", false); check("beam_left_top", false)
check("corner_top_left", true); check("corner_down_left", true)
location:update_visibility(vmath.vector3(-1, -1, -1))
check("wall_left", true)
location:set_node_visible("wall_down", true)
check("wall_down", true); check("corner_down_right", false)
location:set_node_visible("walls", false)
for _, wall in pairs(location.walls) do
    for _, mesh in ipairs(wall.meshes) do check(mesh, false) end
end
check("floor", true); check("area", false)
location:set_node_visible("wall_top", true)
check("wall_top", true)
location:update_visibility(vmath.vector3(-1, -1, -1))
check_corners()

transforms.rotated = math.pi / 2
local rotated = Location:create("rotated", scene)
rotated:update_visibility(vmath.vector3(-1, -1, -1))
assert(not visible["rotated#room"].wall_left and not visible["rotated#room"].wall_down)
assert(visible["rotated#room"].wall_right and visible["rotated#room"].wall_top)
check_corners(visible["rotated#room"])
check("wall_left", true)

local previous_changes = changes
location:update_visibility(vmath.vector3())
assert(changes == previous_changes, "Zero direction preserves visibility")

local empty = Location:create("empty", {})
count = 0
for _, wall in pairs(empty.walls) do
    count = count + 1
    assert(#wall.meshes == 0, "Absent walls have empty lists")
end
assert(count == 8)
empty:update_visibility(vmath.vector3(-1, -1, -1))
print("Location hierarchy, eight wall groups, direct visibility, corners and rotation checks passed")
