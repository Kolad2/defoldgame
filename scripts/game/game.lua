local GameInput = require("scripts.game_input.game_input")
local Character = require("scripts.character.character")
local Camera = require("scripts.camera")

---@class Game
---@field input GameInput
---@field char Character
---@field camera Camera
local Game = {}

function Game:init()
    self.camera = Camera:init()
    self.input = GameInput:create(self)

    local id = go.get_id("/character")
    local controller = self.input:create_controller()
    self.char = Character:create(id, controller)
    msg.post(".", "acquire_input_focus")
end

function Game:update(dt)
    self.char:update(dt)
end

function Game:on_input(action_id, action)
    self.input:on_input(action_id, action)
end

return Game
