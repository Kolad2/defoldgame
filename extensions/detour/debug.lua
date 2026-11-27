-- Call from a render script with the world camera still active.
local M = {}

function M.init(self)
    self.navmesh_predicate = render.predicate({"navmesh"})
    self.navmesh_xray_predicate = render.predicate({"navmesh_xray"})
end

function M.draw(self, options)
    render.set_depth_mask(false)
    render.disable_state(graphics.STATE_CULL_FACE)
    render.enable_state(graphics.STATE_BLEND)
    render.set_blend_func(graphics.BLEND_FACTOR_ONE, graphics.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
    render.enable_state(graphics.STATE_DEPTH_TEST)
    render.set_depth_func(graphics.COMPARE_FUNC_LEQUAL)
    render.draw(self.navmesh_predicate, options)
    render.disable_state(graphics.STATE_DEPTH_TEST)
    render.draw(self.navmesh_xray_predicate, options)
    render.set_depth_func(graphics.COMPARE_FUNC_LESS)
    render.set_blend_func(graphics.BLEND_FACTOR_SRC_ALPHA, graphics.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
end

return M
