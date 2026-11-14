---@class Character
---@field id hash|nil
---@field controller UnitController|nil
local Character = {}
Character.__index = Character


---@param dt number
function Character:update(dt)

end

---@return Character
function Character:create()
    local obj = setmetatable({}, self)
    return obj
end

---@param id hash
---@return Character
function Character:from_go(id)
    local obj = self:create()
    obj.id = id
    return obj
end

return Character
