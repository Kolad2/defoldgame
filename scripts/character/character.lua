---@class Character
local Character = {}
Character.__index = Character

---@return Character
function Character:create()
    local obj = setmetatable({}, self)
    return obj
end

---@param dt number
function Character:update(dt)

end

return Character
