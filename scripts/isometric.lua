local M = {}
M.camera_url = "main:/camera#camera"
M.speed = 2.5
-- world.glb: a 20 x 20 plane at Y = 0. Leave room for the character at its edge.
M.floor_y = 0
M.floor_limit = 9.7

--- Convert physical window pixels to a point on the ground plane.
function M.to_world(x, y)
    local w, h = window.get_size()
    if w <= 0 or h <= 0 then return nil end
    local cam = msg.url(M.camera_url)
    local inverse = vmath.inv(camera.get_projection(cam) * camera.get_view(cam))
    local nx, ny = 2 * x / w - 1, 2 * y / h - 1
    local near = inverse * vmath.vector4(nx, ny, -1, 1)
    local far = inverse * vmath.vector4(nx, ny, 1, 1)
    local origin = vmath.vector3(near.x / near.w, near.y / near.w, near.z / near.w)
    local direction = vmath.vector3(far.x / far.w, far.y / far.w, far.z / far.w) - origin
    if math.abs(direction.y) < 0.000001 then return nil end
    local t = (M.floor_y - origin.y) / direction.y
    if t < 0 then return nil end
    return origin + direction * t
end

--- Ground direction corresponding to a direction on screen, using the actual camera.
function M.screen_direction(x, y)
    local inverse_view = vmath.inv(camera.get_view(msg.url(M.camera_url)))
    local right = inverse_view * vmath.vector4(1, 0, 0, 0)
    local up = inverse_view * vmath.vector4(0, 1, 0, 0)
    return vmath.vector3(right.x * x + up.x * y, 0, right.z * x + up.z * y)
end

function M.clamp_to_map(p)
    local limit = M.floor_limit
    return vmath.vector3(math.max(-limit, math.min(limit, p.x)), M.floor_y,
        math.max(-limit, math.min(limit, p.z)))
end

return M
