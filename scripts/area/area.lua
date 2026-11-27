local dict = require("scripts.tools.dict.init")

local registry = dict:create()
local INTERACTION_GROUPS = { hash("interaction") }

---@class Area
---@field parent any
---@field id hash Game object containing the area's collision object.
local Area = {}
Area.__index = Area

---@param id hash
---@return Area|nil
function Area:get_by_id(id)
    return registry:get(id)
end

---@param from vector3 Ray start in world coordinates.
---@param to vector3 Ray end in world coordinates.
---@return Area|nil area
---@return message.physics.ray_cast_response|nil hit
function Area:find_first(from, to)
    -- TODO: Re-enable raycast after adding a floor collider that creates the physics world.
    -- local hit = physics.raycast(from, to, INTERACTION_GROUPS)
    local hit = nil
    if not hit then return nil end

    local area = self:get_by_id(hit.id)
    if area then return area end

    return nil
end

---@param id hash
---@return Area
function Area:create(id)
    assert(not self:get_by_id(id), "Game object already has an Area")
    ---@type Area
    local obj = setmetatable({}, self)
    obj.id = id
    obj.parent = nil
    registry:set(id, obj)
    return obj
end

return Area
