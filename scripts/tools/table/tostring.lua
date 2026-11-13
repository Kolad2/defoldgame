local base_tostring = tostring

---tostring
---@param tbl table | nil
---@return string
local function tostring(tbl)
    if getmetatable(tbl) and getmetatable(tbl).__tostring then
        return base_tostring(tbl)
    end
    if tbl == nil then return base_tostring(nil) end
    if type(tbl) ~= "table" then return base_tostring(tbl) end
    local str = "{"
    if #tbl == 0 then return str .. "}" end
    if #tbl == 1 then return str .. tostring(tbl[1]) .. "}" end
    str = str .. tostring(tbl[1])
    for i=2, #tbl do
        str = str .. "," .. tostring(tbl[i])
    end
    str = str .. "}"
    return str
end

return tostring