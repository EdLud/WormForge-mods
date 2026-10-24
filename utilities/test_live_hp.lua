-- From the repository root: lua mods/utilities/test_live_hp.lua
local mods = WORMFORGE_MODS or "mods/"
local function run(live_first)
  local hurt, frame = {}, {}
  wa = {
    msg = { FRAME_FINISH = 2 },
    on = {
      hurt = function(fn) hurt[#hurt + 1] = fn end,
      worm_message = function(fn, filter)
        assert(#filter.msgs == 1 and filter.msgs[1] == 2)
        frame[#frame + 1] = fn
      end,
    },
    actors = { spawn = function() error("Live HP must not need a polling actor") end },
  }
  local function load_live() dofile(mods .. "utilities/features/live_hp.lua") end
  local function load_ice()
    local env = setmetatable({ require = function(name)
      assert(name == "lib/shared"); return {}
    end }, { __index = _G })
    assert(loadfile(mods .. "px/weapons/ice_arrow.lua", "t", env))().setup()
  end
  if live_first then load_live(); load_ice() else load_ice(); load_live() end
  local function emit(hit) for _, fn in ipairs(hurt) do fn(hit) end end
  local function forbidden() error("no artificial hit, heal or movement changes") end
  local function worm(id, hp, turn)
    local w = { id = id, hp = hp, turn = turn, vx = 6, vy = -8, state = "hit", commits = 0 }
    w.hurt, w.heal, w.release = forbidden, forbidden, forbidden
    function w:commit_health()
      self.commits = self.commits + 1
      self.display_target = self.hp
      return true
    end
    function w:freeze() self.state = "frozen" end
    return w
  end
  local w = worm(33, 75, false)
  emit{ phase = "pre", kind = "hit", source_weapon = "px.ice_arrow", worm = w, lost = 0 }
  assert(w.commits == 0, "never commit before the hit")
  emit{ phase = "post", kind = "hit", source_weapon = "px.ice_arrow", worm = w, lost = 25 }
  assert(w.commits == 1 and w.display_target == 75 and w.hp == 75)
  for _, fn in ipairs(frame) do fn(w) end
  assert(w.state == "frozen" and w.vx == 6 and w.vy == -8, "Ice Arrow still freezes with original momentum")
  w.hp = 74
  emit{ phase = "post", kind = "poison", worm = w, lost = 1 }
  assert(w.state == "frozen" and w.display_target == 74, "a commit never releases frozen worms")
  for _, kind in ipairs({ "blast", "hit", "percent", "nonlethal", "poison" }) do
    local victim = worm(34, 1, false)
    emit{ phase = "post", kind = kind, worm = victim, lost = 5 }
    assert(victim.commits == 1 and victim.hp == 1 and victim.vx == 6 and victim.vy == -8,
      "one-HP survivors update without pulses or lost momentum")
  end
  for _, damage in ipairs({ 3, 12 }) do
    local victim = worm(35, 0, false) -- a 3 HP worm after lethal damage
    emit{ phase = "post", kind = "hit", source_weapon = "stock.bazooka", worm = victim, lost = 3, amount = damage }
    assert(victim.commits == 1 and victim.display_target == 0 and victim.hp == 0,
      "exact lethal damage and overkill update the label to zero")
    assert(victim.state == "hit" and victim.vx == 6 and victim.vy == -8,
      "the zero-HP victim keeps its normal movement and death sequence")
  end
  for _, v in ipairs({ worm(16, 75, true), worm(16, 0, true) }) do
    emit{ phase = "post", kind = "hit", source_weapon = "stock.bazooka", worm = v, lost = 25 }
    assert(v.commits == 0, "active worms retain normal WA health timing")
  end
  emit{ phase = "post", kind = "hit", worm = w, lost = 0 }
  assert(w.commits == 2, "an eaten or cooldown-blocked hit does not commit")
end
run(true)
run(false)
print("Live HP: Ice Arrow, frozen state, momentum, 1 HP, lethal/overkill display, active timing: PASS")
