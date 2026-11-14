---@class UnitControllerAI : UnitController
local UnitControllerAI = {}
UnitControllerAI.__index = UnitControllerAI

---@return UnitControllerAI
function UnitControllerAI:create()
    local obj = setmetatable({}, self)
    return obj
end

return UnitControllerAI
