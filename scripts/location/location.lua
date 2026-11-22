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

local function walk(nodes, visitor)
    for _, node in ipairs(nodes) do
        local name
        ---@type table|nil
        local children
        if type(node) == "string" then
            name = node
        else
            name, children = next(node)
        end
        visitor(node, name, children)
        if children then walk(children, visitor) end
    end
end

---@param hierarchy table
---@param query string
---@return table|string|nil node
local function find_node(hierarchy, query)
    local found, group_found
    walk(hierarchy, function(node, name, children)
        if name ~= query then return end
        if children then
            assert(not group_found, "Duplicate wall group: " .. query)
            found, group_found = node, true
        elseif not found then
            found = node
        end
    end)
    return found
end

---@param node table|string
---@param available_meshes table<hash, table>
---@return hash[]
local function collect_meshes(node, available_meshes)
    local meshes, seen = {}, {}
    walk({node}, function(_, name)
        local mesh = hash(name)
        -- The hierarchy also contains empty groups; only actual model meshes count.
        if available_meshes[mesh] ~= nil and not seen[mesh] then
            meshes[#meshes + 1] = mesh
            seen[mesh] = true
        end
    end)
    return meshes
end

--- Directly toggle a wall group, all walls, or one mesh.
---@param name string Wall group name, "walls", or a mesh name.
---@param visible boolean
function Location:set_node_visible(name, visible)
    local selected_wall = self.walls[name]
    ---@cast selected_wall Wall|nil
    if name == "walls" then
        for _, wall in pairs(self.walls) do
            wall:set_visible(visible)
        end
    elseif selected_wall then
        selected_wall:set_visible(visible)
    else
        model.set_mesh_enabled(self.model_url, hash(name), visible)
    end
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
---@param hierarchy table Tree decoded from this model's .hierarchy.json.
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
    for _, name in ipairs(WALL_NAMES) do
        local node = find_node(hierarchy, name)
        local meshes = node and collect_meshes(node, available_meshes) or {}
        obj.walls[name] = Wall:create(id, component, meshes)
    end
    return obj
end

return Location
