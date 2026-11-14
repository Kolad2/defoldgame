local GameInput = require("scripts.game_input.game_input")
local Character = require("scripts.character.character")

---@class Game
---@field input GameInput
---@field char Character
local Game = {}

function Game:init()
    self.input = GameInput:create()
    self.char = Character:from_go(go.get_id("/character"))
    msg.post(".", "acquire_input_focus")
end

function Game:update(dt)
    self.char:update(dt)
end

function Game:on_input(action_id, action)
    self.input:on_input(action_id, action)
end

return Game
