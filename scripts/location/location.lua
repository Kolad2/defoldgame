---@class Location
---@field id hash
---@field walls table<string, hash[]?>
---@field private model_url url
local Location = {}
Location.__index = Location

local DIRECTIONS = {
    down = {0, 1},
    right = {1, 0},
    top = {0, -1},
    left = {-1, 0},
}
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
    if name == "walls" then
        for _, meshes in pairs(self.walls) do
            for _, mesh in ipairs(meshes) do
                model.set_mesh_enabled(self.model_url, mesh, visible)
            end
        end
    elseif self.walls[name] then
        for _, mesh in ipairs(self.walls[name]) do
            model.set_mesh_enabled(self.model_url, mesh, visible)
        end
    else
        model.set_mesh_enabled(self.model_url, hash(name), visible)
    end
end

--- Apply visibility from the camera direction; derive corner visibility from wall names.
---@param camera_direction vector3 Direction FROM the camera INTO the scene.
function Location:update_visibility(camera_direction)
    if vmath.length_sqr(camera_direction) < 0.000001 then return end

    go.update_world_transform(self.id)
    local inverse = vmath.inv(go.get_world_transform(self.id))
    local direction = inverse * vmath.vector4(
        camera_direction.x, camera_direction.y, camera_direction.z, 0)
    local toward_camera = -vmath.normalize(vmath.vector3(direction.x, direction.y, direction.z))

    ---@type table<string, boolean>
    local visible = {}
    for side, normal in pairs(DIRECTIONS) do
        local score = normal[1] * toward_camera.x + normal[2] * toward_camera.z
        visible["wall_" .. side] = score <= 0
    end
    for name in pairs(self.walls) do
        local first, second = name:match("^wall_([^_]+)_([^_]+)$")
        local enabled = visible[name]
        if first then
            enabled = visible["wall_" .. first] or visible["wall_" .. second]
        end
        self:set_node_visible(name, enabled)
    end
end

---@param id hash
---@param hierarchy table Tree decoded from this model's .hierarchy.json.
---@param component string|nil Model component id; defaults to "floor".
---@return Location
function Location:create(id, hierarchy, component)
    ---@type Location
    local obj = setmetatable({}, self)
    obj.id = id
    obj.model_url = msg.url(nil, id, component or "floor")
    obj.walls = {}
    local available_meshes = model.get_mesh_aabb(obj.model_url)
    for _, name in ipairs(WALL_NAMES) do
        local node = find_node(hierarchy, name)
        obj.walls[name] = node and collect_meshes(node, available_meshes) or {}
    end
    return obj
end

return Location
