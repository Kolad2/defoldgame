local Wall = require("scripts.location.wall")
local Door = require("scripts.location.door")
local DoorArea = require("scripts.location.door_area")

---@class Location
---@field id hash
---@field walls table<string, Wall>
---@field door Door|nil
---@field private model_url url
local Location = {}
Location.__index = Location

local WALL_NAMES = {
    "wall_down", "wall_right", "wall_top", "wall_left",
    "wall_down_left", "wall_down_right", "wall_top_left", "wall_top_right",
}

---@private
---@param hierarchy GLBHierarchy
---@param component string
---@param available_meshes table<hash, table>
function Location:init_walls(hierarchy, component, available_meshes)
    local walls = {}
    for _, name in ipairs(WALL_NAMES) do
        local node = hierarchy:find_node(name)
        local meshes = node and hierarchy:collect_meshes(node, available_meshes) or {}
        self.walls[name] = Wall:create(self.id, component, meshes)
    end
    return walls
end

---@private
---@param hierarchy GLBHierarchy
---@param component string
---@param available_meshes table<hash, table>
function Location:init_doors(hierarchy, component, available_meshes)
    local door_id = go.get_id("/door_1")
    if not go.exists(door_id) or go.get_parent(door_id) ~= self.id then return end

    local area = hash("area")
    if available_meshes[area] ~= nil then
        model.set_mesh_enabled(self.model_url, area, false)
    end

    ---local area = DoorArea:create(go.get_id("/door_area"))
    ---self.door = Door:create(self, "door_1", area)
    ---area.door = self.door
end

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
    local available_meshes = model.get_mesh_aabb(self.model_url)
    obj.model_url = msg.url(nil, id, component)
    self.walls = obj:init_walls(hierarchy, component, available_meshes)
    self.doors = obj:init_doors(hierarchy, component, available_meshes)
    return obj
end

return Location
