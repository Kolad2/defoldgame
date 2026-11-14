---@class UnitControllerPlayer : UnitController
local UnitControllerPlayer = {}
UnitControllerPlayer.__index = UnitControllerPlayer

---@return UnitControllerPlayer
function UnitControllerPlayer:create()
    local obj = setmetatable({}, self)
    return obj
end

return UnitControllerPlayer
