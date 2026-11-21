local GameInput = require("scripts.game_input.game_input")
local Character = require("scripts.character.character")
local Camera = require("scripts.camera")
local set = require("scripts.tools.set")

---@class Game
---@field input GameInput
---@field char Character
---@field camera Camera
---@field units set<Character>
local Game = {}

function Game:init()
    self.camera = Camera:init()
    self.input = GameInput:create(self)

    local id = go.get_id("/character")
    local brain = self.input:create_brain()
    self.char = Character:create(id, brain)
    self.units = set()
    self.units:add(self.char)
    msg.post(".", "acquire_input_focus")
end

function Game:update(dt)
    for _, unit in ipairs(self.units) do
        unit:update(dt)
    end
end

function Game:on_input(action_id, action)
    self.input:on_input(action_id, action)
end

return Game
