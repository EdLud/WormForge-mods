-- For pack tests: the real wf-lib/tooltip, from sdk/, over a stand-in
-- `wa.hud.window` that hands each text a window opens with or is set to to
-- the test's own `wa.hud.message_top`, with its audience, so a test reads
-- tooltips where it read WA's banner. Call after `wa` is set up:
--   dofile(root .. "../tests/tooltip_mock.lua")(root)
return function(root)
  package.preload["wf-lib/tooltip"] = function() return dofile(root .. "../sdk/tooltip.lua") end
  wa.on.turn_start = wa.on.turn_start or function() end
  wa.on.turn_end = wa.on.turn_end or function() end
  local function record(spec)
    if spec.text then wa.hud.message_top(spec.text, { to = spec.to, alliance = spec.alliance }) end
  end
  wa.hud.window = function(spec)
    record(spec)
    local w = { open = true }
    function w:set(s) record(s); return self.open end
    function w:close() local was = self.open; self.open = false; return was end
    return w
  end
end
