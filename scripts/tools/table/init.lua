---@class (partial) tablelib
---@field find fun(tbl: table, value: any): table
---@field find_first fun(tbl: table, value: any, pos_start: number): table|nil
---@field get_meta_compatible fun(tbl:table,...):table|nil
---@field merge fun(tbl:table|nil,...):table|nil
---@field get_random fun(tbl:table):any
---@field get fun(tbl:table, idx:number):any
---@field empty fun():table
---@field fill fun(tbl:table, value:number|(fun(index:integer):any), pos_start?:integer, pos_end?:integer)
---@field move fun(tbl:table, pos_start:integer, pos_end:integer, pos_to?:integer, tbl_to?:table):table
---@field is_sorted fun(tbl:table):boolean
---@field copy fun(tbl:table, callback?: fun(value:any):any):table
---@field deepcopy fun(tbl:table):table
---@field slice fun(tbl:table, pos_start:number, pos_end:number):table
---@field multiply fun(tbl:table, value:number):table
---@field divide fun(tbl:table, value:number):table
---@field subtract fun(tbl:table, value:number):table
---@field add fun(tbl:table, value:number):table
---@field argmin fun(tbl:table):number
---@field argmax fun(tbl:table):number
---@field min fun(tbl:table):number
---@field max fun(tbl:table):number
---@field cumsum fun(tbl:table):table
---@field sum fun(tbl:table):number
---@field reverse fun(tbl:table):table
---@field shuffle fun(tbl:table):table
---@field remove_swap fun(tbl:table, idx:number):any
---@field remove fun(tbl:table, idx:number):any
---@field tostring fun(tbl:table):string
---@field pack fun(...):table
---@field unpack fun(tbl:table, start_pos:number, end_pos:number)
---@field insert fun(tbl:table, pos:number, value:number):table
local table = require("scripts.tools.table.table")

---@class (partial) tablelib
---@field unique fun(tbl:table):table, dict
table.unique = table.unique or require("scripts.tools.table.unique")

return table


