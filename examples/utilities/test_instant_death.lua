-- From the repository root: lua mods/examples/utilities/test_instant_death.lua
local root = UTILITIES_ROOT or "mods/examples/utilities/"
for _, instant in ipairs({ false, true }) do
  for _, live_hp in ipairs({ false, true }) do
    local frames, hurts, loaded = {}, {}, {}
    local env = setmetatable({}, { __index = _G })
    local wa = {
      msg = { FRAME_FINISH = 2 },
      on = {
        worm_message = function(fn, spec)
          assert(#spec.msgs == 1 and spec.msgs[1] == 2)
          frames[#frames + 1] = fn
        end,
        hurt = function(fn) hurts[#hurts + 1] = fn end,
      },
      log = function() end,
      actors = { spawn = function() error("no map-wide polling actor needed") end },
    }
    env.wa = wa
    env.require = function(name)
      assert(not loaded[name], "a module is installed only once")
      loaded[name] = true
      return assert(loadfile(root .. name .. ".lua", "t", env))()
    end
    local install = assert(loadfile(root .. "features/utilities.lua", "t", env))()
    install{ option = function(key)
      if key == "heal_per_turn" then return 0 end
      if key == "instant_death" then return instant end
      if key == "live_hp" then return live_hp end
      return false
    end }
    assert((#frames == 1) == instant, "Instant Death defaults off and loads only when requested")
    assert((#hurts == 1) == live_hp, "Live HP is an independent switch")
    local function worm(hp, active)
      local w = { hp = hp, turn = active, state = "tumbling", vx = 6, vy = -8, deaths = 0, commits = 0 }
      function w:allow_death()
        if self.permission then return false end
        self.permission, self.deaths = true, self.deaths + 1
        return true
      end
      function w:commit_health() self.commits = self.commits + 1; return true end
      function w:hurt() error("must not add damage") end
      function w:release() error("must not change movement") end
      return w
    end
    local function step(w) for _, fn in ipairs(frames) do fn(w) end end
    local healthy, active, dead = worm(3, false), worm(0, true), worm(0, false)
    for _, w in ipairs({ healthy, active, dead }) do
      step(w)
      assert(w.hp >= 0 and w.state == "tumbling" and w.vx == 6 and w.vy == -8)
    end
    assert(healthy.deaths == 0 and active.deaths == 0)
    assert(dead.deaths == (instant and 1 or 0), "zero HP requests native death without Live HP")
    step(dead)
    assert(dead.deaths == (instant and 1 or 0), "repeated frames cannot restart a death")
    local second = worm(0, false)
    step(second)
    assert(second.deaths == (instant and 1 or 0), "several casualties receive their own permission")
    local from_fall = worm(0, false)
    step(from_fall)
    assert(from_fall.deaths == (instant and 1 or 0), "zero HP needs no hurt callback")
    for _, fn in ipairs(hurts) do fn{ phase = "post", lost = 3, worm = dead } end
    assert(dead.commits == (live_hp and 1 or 0))
  end
end
print("Instant Death: default off, independent switches, active/surviving worms, multiple casualties and movement: PASS")
