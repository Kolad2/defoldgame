---@class Location
---@field id hash
---@field private model_url url
---@field private groups table<string, hash[]>
---@field private aliases table<string, string>
---@field private hidden_nodes table<string, boolean>
---@field private directional_nodes table<string, vector3[]>
---@field private directional_hidden table<string, boolean>
---@field private camera_hidden table<string, boolean>
---@field private visibility_links table<string, string[]>
---@field private mesh_visibility table<hash, boolean>
local Location = {}
Location.__index = Location
Location.VISIBILITY_THRESHOLD = 0.05

---@private
function Location:_apply_visibility()
    -- Combine independent manual and camera masks; both apply to complete subtrees.
    local hidden_meshes = {}
    for path, meshes in pairs(self.groups) do
        if self.hidden_nodes[path] or self.camera_hidden[path] then
            for _, mesh in ipairs(meshes) do
                hidden_meshes[mesh] = true
            end
        end
    end
    for mesh, was_visible in pairs(self.mesh_visibility) do
        local enabled = not hidden_meshes[mesh]
        if enabled ~= was_visible then
            model.set_mesh_enabled(self.model_url, mesh, enabled)
            self.mesh_visibility[mesh] = enabled
        end
    end
end

--- Toggle a named node and its subtree. Camera visibility still applies.
---@param node string Use its full path if the name is ambiguous.
---@param visible boolean
function Location:set_node_visible(node, visible)
    local path = self.aliases[node] or node
    assert(self.groups[path], "Unknown or ambiguous location node: " .. node)
    self.hidden_nodes[path] = not visible or nil
    self:_apply_visibility()
end

--- Recalculate direction-dependent groups using the camera's world-space forward.
---@param camera_direction vector3 Direction FROM the camera INTO the scene.
function Location:update_visibility(camera_direction)
    if vmath.length_sqr(camera_direction) < 0.000001 then return end

    go.update_world_transform(self.id)
    local inverse = vmath.inv(go.get_world_transform(self.id))
    local direction = inverse * vmath.vector4(
        camera_direction.x, camera_direction.y, camera_direction.z, 0)
    local toward_camera = -vmath.normalize(vmath.vector3(direction.x, direction.y, direction.z))
    local changed = false

    for path, normals in pairs(self.directional_nodes) do
        local score = -math.huge
        -- Multiple directions are useful for groups with several outward faces.
        for _, normal in ipairs(normals) do
            score = math.max(score, vmath.dot(normal, toward_camera))
        end
        local was_hidden = self.directional_hidden[path]
        local hidden = was_hidden
        if was_hidden == nil then
            hidden = score > 0
        elseif score > self.VISIBILITY_THRESHOLD then
            hidden = true
        elseif score < -self.VISIBILITY_THRESHOLD then
            hidden = false
        end
        if hidden ~= was_hidden then
            self.directional_hidden[path] = hidden
            changed = true
        end
    end
    if not changed then return end

    -- Neighbor rules belong only to camera visibility. Manual hiding is independent.
    local hidden, checking = {}, {}
    local function is_camera_hidden(path)
        if hidden[path] ~= nil then return hidden[path] end
        assert(not checking[path], "Cyclic camera visibility dependency: " .. path)
        checking[path] = true
        local result = self.directional_hidden[path] or false
        local parent = path:match("^(.*)/[^/]+$")
        if not result and parent and self.groups[parent] then
            result = is_camera_hidden(parent)
        end
        local neighbors = self.visibility_links[path]
        if not result and neighbors then
            result = true
            for _, neighbor in ipairs(neighbors) do
                if not is_camera_hidden(neighbor) then
                    result = false
                    break
                end
            end
        end
        checking[path] = nil
        hidden[path] = result
        return result
    end
    for path in pairs(self.groups) do is_camera_hidden(path) end
    self.camera_hidden = hidden
    self:_apply_visibility()
end

---@param id hash
---@param scene table Hierarchy decoded from the JSON beside this model's GLB.
---@param component string|nil Model component id; defaults to "floor".
---@return Location
function Location:create(id, scene, component)
    assert(scene, "Location hierarchy data is missing")
    ---@type Location
    local obj = setmetatable({}, self)
    obj.id = id
    obj.model_url = msg.url(nil, id, component or "floor")
    obj.groups = {}
    obj.aliases = scene.aliases
    obj.hidden_nodes = {}
    obj.directional_nodes = {}
    obj.directional_hidden = {}
    obj.camera_hidden = {}
    obj.visibility_links = scene.visibility_links or {}
    obj.mesh_visibility = {}
    for path, meshes in pairs(scene.groups) do
        local ids = {}
        for _, name in ipairs(meshes) do
            local mesh = hash(name)
            ids[#ids + 1] = mesh
            if obj.mesh_visibility[mesh] == nil then
                obj.mesh_visibility[mesh] = model.get_mesh_enabled(obj.model_url, mesh)
            end
        end
        obj.groups[path] = ids
    end
    for path, normals in pairs(scene.visibility or {}) do
        local vectors = {}
        for _, normal in ipairs(normals) do
            vectors[#vectors + 1] = vmath.vector3(normal[1], normal[2], normal[3])
        end
        obj.directional_nodes[path] = vectors
    end
    return obj
end

return Location
