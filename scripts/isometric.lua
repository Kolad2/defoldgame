local M = {}
M.width, M.height = 1920, 1080
M.pixels_per_unit = 110
M.speed = 1.25
local r = math.sqrt(0.5)
local u = 1 / math.sqrt(6)

-- Game objects are placed directly in image/scene coordinates (XY pixels).
-- Ground-space XZ coordinates are used only for movement speed and direction.
-- The model stores the isometric rotation; the collection uses 110 px/unit scale.
local scene_up = vmath.vector3(0, math.sqrt(2/3), 1/math.sqrt(3))

function M.scene_rotation(angle)
    return vmath.quat_axis_angle(scene_up, angle)
end

function M.to_world(x, y)
    local sx = (x - M.width / 2) / M.pixels_per_unit
    local sy = (y - M.height / 2) / M.pixels_per_unit
    return vmath.vector3((sy/u-sx/r)/2, 0, (sy/u+sx/r)/2)
end

function M.to_image(p)
    return M.width/2 + M.pixels_per_unit*r*(p.z-p.x),
           M.height/2 + M.pixels_per_unit*u*(p.x+p.z)
end

function M.viewport(w, h)
    local scale = math.min(w/M.width, h/M.height)
    local vw, vh = math.floor(M.width*scale), math.floor(M.height*scale)
    return math.floor((w-vw)/2), math.floor((h-vh)/2), vw, vh
end

function M.clamp_to_map(p)
    local x, y = M.to_image(p)
    return M.to_world(math.max(35, math.min(M.width-35, x)), math.max(35, math.min(M.height-200, y)))
end

return M
