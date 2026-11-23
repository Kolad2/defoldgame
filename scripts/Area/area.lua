local dict = require("scripts.tools.dict.init")

local registry = dict:create()

---@class Area
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
---@return bullet3d.world.cast_result|nil hit
function Area:find_first(from, to)
    local world = bullet3d.get_world()
    if not world then return nil end

    for _, hit in ipairs(bullet3d.world.cast_ray(world, from, to - from)) do
        local id = bullet3d.get_gameobject_id(hit.object)
        local area = id and self:get_by_id(id)
        if area then return area end
    end

    return nil
end

---@param id hash
---@return Area
function Area:create(id)
    assert(not self:get_by_id(id), "Game object already has an Area")
    ---@type Area
    local obj = setmetatable({}, self)
    obj.id = id
    registry:set(id, obj)
    return obj
end

return Area
