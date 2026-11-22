-- For pack tests: `wa.draw.brush` over the test's own `wa.draw.quad`, so a
-- brush's boxes reach the test as the quads the engine draws for them:
-- the brush's fields, and `points` at the box's corners, from its top-left
-- clockwise, turned `angle` radians about its centre. Call after `wa` is
-- set up:
--   dofile(root .. "../tests/brush_mock.lua")(wa)
return function(wa)
  wa.draw = wa.draw or {}
  wa.draw.brush = function(spec)
    local brush = {}
    function brush:box(x, y, w, h, angle, frame, color, visibility)
      local c, s = math.cos(angle or 0), math.sin(angle or 0)
      local hw, hh = w / 2, h / 2
      local points = {}
      for i, d in ipairs({ { -hw, -hh }, { hw, -hh }, { hw, hh }, { -hw, hh } }) do
        points[i] = { x + d[1] * c - d[2] * s, y + d[1] * s + d[2] * c }
      end
      wa.draw.quad({
        sprite = spec.sprite, frame = frame or spec.frame or 0, blend = spec.blend, depth = spec.depth,
        color = color or spec.color, colors = not color and spec.colors or nil, uv = spec.uv,
        points = points, visibility = visibility,
      })
    end
    return brush
  end
end
