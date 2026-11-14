---@class Character
---@field id hash
---@field controller UnitController
local Character = {}
Character.__index = Character


---@param dt number
function Character:update(dt)

end

---@param id hash
---@param controller UnitController
---@return Character
function Character:create(id, controller)
    local obj = setmetatable({}, self)
    obj.id = id
    obj.controller = controller
    return obj
end

return Character
