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

---@param id hash
---@param component string|nil Model component id; defaults to "room".
---@return Wall
function Wall:create(id, component)
    ---@type Wall
    local obj = setmetatable({}, self)
    obj.id = id
    obj.model_url = msg.url(nil, id, component or "room")
    obj.meshes = {}
    return obj
end

return Wall
