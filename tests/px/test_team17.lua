-- From the mods root: lua tests/px/test_team17.lua
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local frame, rolls, worms, crates, spawned, banners, windows = 0, {}, {}, {}, {}, {}, {}
local on
-- wa.random takes its answers from `rolls` in turn (then the lowest).
wa = {
  msg = { FRAME_FINISH = 1, WEAPON_RELEASED = 2 },
  log = function() end,
  random = function(a, b)
    local r = table.remove(rolls, 1)
    return r and math.min(b, math.max(a, r)) or a
  end,
  -- As WA's: a worm at 0 HP is no longer listed.
  worms = { all = function()
    local alive = {}
    for _, w in ipairs(worms) do if w.hp > 0 then alive[#alive + 1] = w end end
    return alive
  end },
  world = {
    frame = function() return frame end,
    size = function() return { w = 100, h = 100 } end,
    water = function() return 90 end,
    -- Land above y 50 and at y 60 below: a crate's box (a short sweep) fits from 50 down.
    trace = function(t)
      if t.y1 - t.y0 < 10 then
        return t.y0 + 2.5 < 50 and { hit = false, starts_solid = true } or nil
      end
      return { hit = true, x = t.x0, y = 60 }
    end,
  },
  crates = {
    all = function() return crates end,
    spawn = function(spec)
      spawned[#spawned + 1] = spec
      local c = { kind = spec.kind }
      crates[#crates + 1] = c
      return c
    end,
  },
  hud = {
    message_top = function(t) banners[#banners + 1] = t end,
    window = function(spec)
      local w = { spec = spec, open = true }
      function w:close() self.open = false end
      windows[#windows + 1] = w
      return w
    end,
  },
  on = {},
}
local function reset_hooks()
  on = { turn_start = {}, turn_end = {}, worm_message = {}, death = {} }
  for name, list in pairs(on) do wa.on[name] = function(f) list[#list + 1] = f end end
end
local function fire(name, ...) for _, f in ipairs(on[name]) do f(...) end end

local delays = {}
local function worm(id, team)
  local w = { id = id, team = team, ammo_group = team, hp = 100, turn = false }
  function w:heal(n) self.hp = self.hp + n end
  function w:delay(weapon, turns)
    delays[self.ammo_group] = delays[self.ammo_group] or {}
    if turns == nil then return delays[self.ammo_group][weapon] or 0 end
    delays[self.ammo_group][weapon] = turns
  end
  return w
end
local function delay(group, weapon) return (delays[group] or {})[weapon] or 0 end

local PLACED = {}
for _, id in ipairs({
  "stock.fire_punch", "stock.dragon_ball", "stock.prod", "stock.blow_torch", "stock.pneumatic_drill",
  "stock.girder", "px.super_tele", "stock.low_gravity", "px.double_bazooka", "px.underwater_bomb",
  "px.wind_changer",
}) do PLACED[id] = {} end

reset_hooks()
require("scheme/team17").install({ weapons = PLACED })

local function step(w)
  frame = frame + 1
  fire("worm_message", w, wa.msg.FRAME_FINISH)
end
-- WA's death event: the worm's HP reaches 0.
local function kill(w)
  w.hp = 0
  fire("death", { victim = w })
end
local function turn(w)
  for _, o in ipairs(worms) do o.turn = o == w end
  fire("turn_start", { worm = w })
  step(w)
end

worms = { worm(1, 1), worm(17, 2), worm(18, 2) }
local a, b, b2 = worms[1], worms[2], worms[3]
local old_crate = { kind = "weapon" }
crates = { old_crate }

turn(a)
check("the rules window opens at the first turn", #windows == 1 and windows[1].open)
check("crates out at the turn start keep the camera", old_crate.camera == false)

-- A kill: 30 HP, then a utility crate and a weapon crate.
rolls = {
  1, 0, 0, -- the utility crate: Crate Grabber (not placed: Low Gravity); its spot
  2, -- the weapon crate's list: normal
  17, -- Underwater Bomb, three of them
  0, 0, -- its spot
}
kill(b)
step(a)
check("the killer gets 30 HP", a.hp == 130, a.hp)
check("two crates", #spawned == 2, #spawned)
check("utility crate: Low Gravity in place of an unplaced weapon",
  spawned[1].kind == "utility" and spawned[1].contents == "stock.low_gravity", spawned[1].contents)
check("weapon crate: three Underwater Bombs",
  spawned[2].kind == "weapon" and spawned[2].contents == "px.underwater_bomb" and spawned[2].amount == 3)
check("the crates land on free ground", spawned[1].y >= 50 and spawned[1].y < 90, spawned[1].y)
check("a crate made in a turn doesn't pull the camera", crates[#crates].camera == false)
step(a)
check("a kill counts once", #spawned == 2 and a.hp == 130)

-- A worm of the turn's own team gives nothing; nor a worm dying on its own turn.
spawned = {}
for _, w in ipairs(worms) do w.hp = 100 end
step(a)
turn(b)
kill(b2)
step(b)
check("no reward for a teammate", #spawned == 0 and b.hp == 100)

-- An unplaced weapon gives a random weapon crate.
fire("turn_end")
b2.hp = 100
step(b)
turn(a)
rolls = { 1, 0, 0, 9, 1, 0, 0 } -- utility crate; super list; Burning Sheep Launcher (not placed)
kill(b)
step(a)
check("an unplaced weapon: a random weapon crate", spawned[2] and spawned[2].contents == nil and spawned[2].kind == "weapon")

-- One F4 weapon a turn: the punch locks the punches and the Super Tele.
a.weapon = "stock.fire_punch"
fire("worm_message", a, wa.msg.WEAPON_RELEASED)
check("F4: the Dragon Ball is locked", delay(1, "stock.dragon_ball") == -1)
check("F4: the Super Tele is locked", delay(1, "px.super_tele") == -1)
check("F4: the F7 weapons stay", delay(1, "stock.girder") == 0)
a.weapon = "stock.girder"
fire("worm_message", a, wa.msg.WEAPON_RELEASED)
check("F7: the BlowTorch is locked", delay(1, "stock.blow_torch") == -1)
a.weapon = "px.double_bazooka"
fire("worm_message", a, wa.msg.WEAPON_RELEASED)
check("another weapon locks nothing", delay(1, "px.double_bazooka") == 0)
delays[1]["stock.prod"] = 3 -- a delay of its own is left alone
fire("turn_end")
check("the turn's end lifts the locks", delay(1, "stock.dragon_ball") == 0 and delay(1, "px.super_tele") == 0
  and delay(1, "stock.blow_torch") == 0)
check("a delay that wasn't a lock stays", delay(1, "stock.prod") == 3)
check("crates pull the camera again between turns", old_crate.camera == nil)

-- The health crate: after 18000 frames and some of 7200, while at most four crates are out.
crates, spawned, banners = {}, {}, {}
for _, w in ipairs(worms) do w.hp = 100 end
reset_hooks()
package.loaded["scheme/team17"] = nil
require("scheme/team17").install({ weapons = PLACED })
rolls = { 100 } -- 18100 frames
turn(b)
for _ = 1, 18099 do step(b) end
check("no health crate yet", #spawned == 0)
rolls = { 0, 0 }
step(b)
check("a health crate of 75", #spawned == 1 and spawned[1].kind == "health" and spawned[1].health == 75)
check("its banner", banners[1] == "Health crate spawned.")
check("the rules window closes after ten seconds", not windows[2].open)

if failed > 0 then
  print(failed .. " Team17 check(s) failed")
  os.exit(1)
end
print("Team17 rules: all checks passed")
