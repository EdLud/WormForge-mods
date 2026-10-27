-- From the repository root: lua mods/utilities/test_instant_death.lua
local root = UTILITIES_ROOT or "mods/utilities/"
for _, instant in ipairs({ "off", "settled", "in_flight", true }) do
  local on, flies = instant ~= "off", instant == "in_flight"
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
    assert((#frames == 1) == on, "Instant Death defaults off and loads only when requested")
    assert((#hurts == 1) == live_hp, "Live HP is an independent switch")
    local function worm(hp, active)
      local w = { hp = hp, turn = active, state = "tumbling", vx = 6, vy = -8, deaths = 0, commits = 0, died = 0 }
      -- WA's death started now: true once, then the worm is in its death.
      function w:die()
        assert(flies, "only in_flight starts a death in flight")
        if self.dying or self.hp > 0 then return false end
        self.dying, self.died = true, self.died + 1
        return true
      end
      function w:allow_death()
        -- WA refuses a worm already in its death, as the engine does.
        if self.permission or self.dying then return false end
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
    -- In flight, WA's death starts at once; settled, WA gets the permission.
    -- Either way one death per worm.
    local function died(w) return w.died + w.deaths end
    assert(died(healthy) == 0 and died(active) == 0)
    assert(died(dead) == (on and 1 or 0), "zero HP starts native death without Live HP")
    assert(dead.died == (flies and 1 or 0), "in_flight dies where it flies")
    step(dead)
    assert(died(dead) == (on and 1 or 0), "repeated frames cannot restart a death")
    assert(dead.died == (flies and 1 or 0), "one death start in flight")
    local second = worm(0, false)
    step(second)
    assert(died(second) == (on and 1 or 0), "several casualties receive their own death")
    local from_fall = worm(0, false)
    step(from_fall)
    assert(died(from_fall) == (on and 1 or 0), "zero HP needs no hurt callback")
    if flies then
      -- One WA won't start in flight (the Kamikaze's) still dies when settled.
      local kamikaze = worm(0, false)
      function kamikaze:die() return false end
      step(kamikaze)
      assert(kamikaze.deaths == 1, "falls back to WA's own death")
    end
    for _, fn in ipairs(hurts) do fn{ phase = "post", lost = 3, worm = dead } end
    assert(dead.commits == (live_hp and 1 or 0))
  end
end
print("Instant Death: default off, independent switches, active/surviving worms, multiple casualties and movement: PASS")
