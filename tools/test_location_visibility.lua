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
local scene = {
    groups = {room = {"floor"}, ["room/walls"] = {}, ["room/floor"] = {"floor"}},
    aliases = {room = "room", walls = "room/walls", floor = "room/floor"},
    visibility = {}, visibility_links = {},
}
local function group(name, meshes)
    local path = "room/walls/" .. name
    scene.aliases[name] = path
    scene.groups[path] = meshes
    for _, mesh in ipairs(meshes) do
        table.insert(scene.groups.room, mesh)
        table.insert(scene.groups["room/walls"], mesh)
    end
    return path
end
for name, normal in pairs({down = {0, 0, 1}, right = {1, 0, 0},
                          top = {0, 0, -1}, left = {-1, 0, 0}}) do
    scene.visibility[group("wall_" .. name, {"wall_" .. name, "beam_" .. name .. "_top"})] = {normal}
end
for name, neighbors in pairs({down_left = {"down", "left"}, down_right = {"down", "right"},
                             top_left = {"top", "left"}, top_right = {"top", "right"}}) do
    scene.visibility_links[group("wall_" .. name, {"corner_" .. name})] = {
        scene.aliases["wall_" .. neighbors[1]], scene.aliases["wall_" .. neighbors[2]],
    }
end
local location = Location:create("bar", scene)
local state = visible["bar#floor"]
local function check(wall, expected) assert(state[wall] == expected, wall) end
local function check_corners(s)
    s = s or state
    assert(s.corner_down_left == (s.wall_down or s.wall_left), "down-left corner")
    assert(s.corner_down_right == (s.wall_down or s.wall_right), "down-right corner")
    assert(s.corner_top_left == (s.wall_top or s.wall_left), "top-left corner")
    assert(s.corner_top_right == (s.wall_top or s.wall_right), "top-right corner")
end

location:update_visibility(vmath.vector3(-1, -1, -1))
check("wall_down", false); check("wall_right", false)
check("wall_top", true); check("wall_left", true)
check("corner_down_left", true); check("corner_down_right", false)
check("corner_top_right", true); check("corner_top_left", true)
check_corners()
check("beam_down_top", false); check("floor", true)
local count = changes
location:update_visibility(vmath.vector3(-1, -1, -1))
assert(changes == count, "Unchanged camera must not toggle meshes")

-- Manual hiding does not influence the camera's corner rules, even after updates.
location:set_node_visible("wall_left", false)
check("wall_left", false); check("wall_down", false)
check("corner_down_left", true)
location:update_visibility(vmath.vector3(-1, -1, -1))
check("corner_down_left", true)
location:update_visibility(vmath.vector3(1, -1, -1))
check("corner_down_left", false)
location:update_visibility(vmath.vector3(-1, -1, -1))
check("wall_left", false); check("corner_down_left", true)
location:set_node_visible("wall_left", true)
check("corner_down_left", true); check_corners()

location:set_node_visible("wall_top", false)
location:set_node_visible("wall_left", false)
check("wall_top", false); check("wall_left", false)
check("corner_top_left", true)
location:update_visibility(vmath.vector3(-1, -2, -1))
check("corner_top_left", true)
location:set_node_visible("wall_top", true)
location:set_node_visible("wall_left", true)
check_corners()

-- Explicit hiding of a corner remains independent of camera changes as well.
location:set_node_visible("wall_top_left", false)
location:update_visibility(vmath.vector3(-1, -1, -1))
check("corner_top_left", false)
location:set_node_visible("wall_top_left", true)
check_corners()

location:update_visibility(vmath.vector3(1, -1, 1))
check("wall_down", true); check("wall_right", true)
check("wall_top", false); check("wall_left", false)
check("corner_top_left", false); check("corner_down_right", true)
check_corners()

-- On either side of the threshold, retain the previous state until it is crossed.
location:update_visibility(vmath.vector3(0.01, 0, -1))
check("wall_right", true); check("wall_left", false)
check_corners()
location:update_visibility(vmath.vector3(-0.01, 0, -1))
check("wall_right", true); check("wall_left", false)
check_corners()
location:update_visibility(vmath.vector3(-0.1, 0, -1))
check("wall_right", false); check("wall_left", true)
check_corners()

location:set_node_visible("walls", false)
location:update_visibility(vmath.vector3(-1, -1, -1))
check("wall_top", false)
check_corners()
location:set_node_visible("wall_top", true)
check("wall_top", false)
location:set_node_visible("walls", true)
check("wall_top", true); check("wall_down", false)
check_corners()

for _, direction in ipairs({{-1, -1, -1}, {1, -1, -1}, {1, -1, 1}, {-1, -1, 1}}) do
    location:update_visibility(vmath.vector3(direction[1], direction[2], direction[3]))
    check_corners()
end
location:update_visibility(vmath.vector3(-1, -1, -1))

transforms.rotated = math.pi / 2
local rotated = Location:create("rotated", scene)
rotated:update_visibility(vmath.vector3(-1, -1, -1))
assert(not visible["rotated#floor"].wall_left and not visible["rotated#floor"].wall_down)
assert(visible["rotated#floor"].wall_right and visible["rotated#floor"].wall_top)
check_corners(visible["rotated#floor"])
check("wall_left", true) -- The other instance's rules/state remain independent.

count = changes
location:update_visibility(vmath.vector3())
assert(changes == count, "Zero camera direction must preserve visibility")

-- Before the first camera update, manual operations must not evaluate neighbor links.
local manual = Location:create("manual", scene)
manual:set_node_visible("wall_top", false)
manual:set_node_visible("wall_left", false)
assert(visible["manual#floor"].corner_top_left)
print("Location direction, hysteresis, hierarchy and rotation checks passed")
