---
--- Created by Koladik
--- DateTime: 19.11.2026 18:53
---

local WALK = "Mixamo | Catwalk Walk Forward"

---@class AnimationPlayer
---@field private model_url url
---@field private moving boolean
local AnimationPlayer = {}
AnimationPlayer.__index = AnimationPlayer

---@param moving boolean
function AnimationPlayer:set_walking(moving)
    if self.moving == moving then return end
    self.moving = moving
    go.set(self.model_url, "playback_rate", moving and 1 or 0)
    if not moving then go.set(self.model_url, "cursor", 0) end
end

---@param id hash
---@return AnimationPlayer
function AnimationPlayer:create(id)
    local obj = setmetatable({}, self)
    obj.model_url = msg.url(nil, id, "model")
    obj.moving = false
    model.play_anim(obj.model_url, WALK, go.PLAYBACK_LOOP_FORWARD, { playback_rate = 0 })
    return obj
end

return AnimationPlayer
