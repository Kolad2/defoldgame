---
--- Created by Koladik
--- DateTime: 22.11.2026 7:08
---

---@class Wall
---@field id hash Game object containing the location model.
---@field model_url url
---@field meshes hash[]
local Wall = {}
Wall.__index = Wall

---@param visible boolean
function Wall:set_visible(visible)
    for _, mesh in ipairs(self.meshes) do
        model.set_mesh_enabled(self.model_url, mesh, visible)
    end
end

---@param id hash
---@param component string Model component id.
---@param meshes hash[]
---@return Wall
function Wall:create(id, component, meshes)
    ---@type Wall
    local obj = setmetatable({}, self)
    obj.id = id
    obj.model_url = msg.url(nil, id, component)
    obj.meshes = meshes
    return obj
end

return Wall
