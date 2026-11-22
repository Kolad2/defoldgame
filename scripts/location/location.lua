local Wall = require("scripts.location.wall")

---@class Location
---@field id hash
---@field walls table<string, Wall>
---@field private model_url url
local Location = {}
Location.__index = Location

local WALL_NAMES = {
    "wall_down", "wall_right", "wall_top", "wall_left",
    "wall_down_left", "wall_down_right", "wall_top_left", "wall_top_right",
}

--- Show far walls and any corners adjacent to a visible wall.
---@param camera_direction vector3 Direction FROM the camera INTO the scene.
function Location:update_visibility(camera_direction)
    if vmath.length_sqr(camera_direction) < 0.000001 then return end

    go.update_world_transform(self.id)
    local inverse = vmath.inv(go.get_world_transform(self.id))
    local direction = inverse * vmath.vector4(
        camera_direction.x, camera_direction.y, camera_direction.z, 0)
    local down = direction.z >= 0
    local top = direction.z <= 0
    local right = direction.x >= 0
    local left = direction.x <= 0

    self.walls.wall_down:set_visible(down)
    self.walls.wall_top:set_visible(top)
    self.walls.wall_right:set_visible(right)
    self.walls.wall_left:set_visible(left)
    self.walls.wall_down_left:set_visible(down or left)
    self.walls.wall_down_right:set_visible(down or right)
    self.walls.wall_top_left:set_visible(top or left)
    self.walls.wall_top_right:set_visible(top or right)
end

---@param id hash
---@param hierarchy GLBHierarchy
---@param component string|nil Model component id; defaults to "room".
---@return Location
function Location:create(id, hierarchy, component)
    component = component or "room"
    ---@type Location
    local obj = setmetatable({}, self)
    obj.id = id
    obj.model_url = msg.url(nil, id, component)
    obj.walls = {}
    local available_meshes = model.get_mesh_aabb(obj.model_url)
    local area = hash("area")
    if available_meshes[area] ~= nil then
        model.set_mesh_enabled(obj.model_url, area, false)
    end
    for _, name in ipairs(WALL_NAMES) do
        local node = hierarchy:find_node(name)
        local meshes = node and hierarchy:collect_meshes(node, available_meshes) or {}
        obj.walls[name] = Wall:create(id, component, meshes)
    end
    return obj
end

return Location
