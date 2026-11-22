---@class GLBHierarchy
---@field private nodes table
local GLBHierarchy = {}
GLBHierarchy.__index = GLBHierarchy

local function walk_nodes(nodes, visitor)
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
        if children then walk_nodes(children, visitor) end
    end
end

---@param visitor fun(node: table|string, name: string, children: table|nil)
---@param node table|string|nil Subtree root; omit to walk the whole hierarchy.
function GLBHierarchy:walk(visitor, node)
    walk_nodes(node and {node} or self.nodes, visitor)
end

---@param query string
---@return table|string|nil node
function GLBHierarchy:find_node(query)
    local found, group_found
    self:walk(function(node, name, children)
        if name ~= query then return end
        if children then
            assert(not group_found, "Duplicate hierarchy group: " .. query)
            found, group_found = node, true
        elseif not found then
            found = node
        end
    end)
    return found
end

---@param node table|string
---@param available_meshes table<hash, table> Actual meshes from model.get_mesh_aabb().
---@return hash[]
function GLBHierarchy:collect_meshes(node, available_meshes)
    local meshes, seen = {}, {}
    self:walk(function(_, name)
        local mesh = hash(name)
        -- Empty groups have no corresponding mesh in the model.
        if available_meshes[mesh] ~= nil and not seen[mesh] then
            meshes[#meshes + 1] = mesh
            seen[mesh] = true
        end
    end, node)
    return meshes
end

---@param nodes table Tree decoded from a .hierarchy.json file.
---@return GLBHierarchy
function GLBHierarchy:create(nodes)
    ---@type GLBHierarchy
    local obj = setmetatable({}, self)
    obj.nodes = nodes
    return obj
end

---@param source string JSON hierarchy contents.
---@return GLBHierarchy
function GLBHierarchy:from_json(source)
    return self:create(json.decode(source))
end

return GLBHierarchy
