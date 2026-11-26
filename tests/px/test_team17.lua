-- From the mods root: lua tests/px/test_team17.lua
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local frame, rolls, worms, crates, spawned, banners, windows, tray = 0, {}, {}, {}, {}, {}, {}, {}
-- This machine's keys held, WA's panel on the screen (nil: shut) and the
-- HUD's text this frame.
local held, stock_panel, closes, texts = {}, nil, 0, {}
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
  -- crate_spot's row check of the crate's box: land above y 50.
  land = { trace = function(_, y0) return y0 < 50 end },
  panel = {
    stock = function() return stock_panel end,
    close = function() closes = closes + 1 return true end,
  },
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
    key = function(name) return held[name] == true end,
    text = function(t) texts[#texts + 1] = t end,
    window = function(spec)
      local w = { spec = spec, open = true }
      function w:close() self.open = false end
      function w:is_open() return self.open end
      windows[#windows + 1] = w
      return w
    end,
    -- As the engine's: one entry per team and weapon or text, oldest first.
    tray = { add = function(spec)
      for _, e in ipairs(tray) do
        if e.team == spec.team and e.weapon == spec.weapon and e.text == spec.text then return e end
      end
      local e = { weapon = spec.weapon, text = spec.text, team = spec.team, greyed = spec.greyed or false }
      function e:set(t) for k, v in pairs(t) do self[k] = v end return true end
      tray[#tray + 1] = e
      return e
    end },
  },
  on = {},
}
local function reset_hooks()
  on = { turn_start = {}, turn_end = {}, worm_message = {}, death = {}, hud = {} }
  for name, list in pairs(on) do wa.on[name] = function(f) list[#list + 1] = f end end
end
local function fire(name, ...) for _, f in ipairs(on[name]) do f(...) end end

local delays = {}
local function worm(id, team)
  local w = { id = id, team = team, ammo_group = team, hp = 100, turn = false }
  function w:heal(n) self.hp = self.hp + n end
  function w:ammo() return -1 end
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
  texts = {}
  fire("hud")
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
local function cell(team, text)
  for _, e in ipairs(tray) do
    if e.team == team and e.text == text then return e end
  end
end
check("the tray reads F4, F7, Super Tele from the left", #tray == 3 and tray[1].weapon == "px.super_tele"
  and tray[2].text == "F7" and tray[3].text == "F4" and tray[1].team == 1)
check("nothing greyed at the turn's start", not cell(1, "F4").greyed and not cell(1, "F7").greyed)
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
step(a)
check("F4: its cell greys", cell(1, "F4").greyed and not cell(1, "F7").greyed)
a.weapon = "stock.girder"
fire("worm_message", a, wa.msg.WEAPON_RELEASED)
check("F7: the BlowTorch is locked", delay(1, "stock.blow_torch") == -1)
step(a)
check("F7: its cell greys", cell(1, "F7").greyed)
a.weapon = "px.double_bazooka"
fire("worm_message", a, wa.msg.WEAPON_RELEASED)
check("another weapon locks nothing", delay(1, "px.double_bazooka") == 0)
delays[1]["stock.prod"] = 3 -- a delay of its own is left alone
fire("turn_end")
check("the turn's end lifts the locks", delay(1, "stock.dragon_ball") == 0 and delay(1, "px.super_tele") == 0
  and delay(1, "stock.blow_torch") == 0)
check("a delay that wasn't a lock stays", delay(1, "stock.prod") == 3)
check("crates pull the camera again between turns", old_crate.camera == nil)
turn(b)
check("each team its own cells", #tray == 6 and cell(2, "F4") and not cell(2, "F4").greyed)
fire("turn_end")
turn(a)
check("the next turn: ungreyed, the same cells", #tray == 6 and not cell(1, "F4").greyed and not cell(1, "F7").greyed)

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

-- Shift + T: the rules again, the panel shut; a second press closes them.
local function press()
  held = { shift = true, t = true }
  step(b)
  held = {}
  step(b)
end
local before = #windows
stock_panel = { x = 100, y = 200, w = 177, h = 159, open = true, opened = 1, cells = {} }
step(b)
check("the note above the open panel", texts[1] and texts[1].text == "Shift + T = scheme info"
  and texts[1].align == "right" and texts[1].x == 277 and texts[1].y < 200)
press()
check("Shift + T opens the rules", #windows == before + 1 and windows[#windows].open)
check("Shift + T shuts the open panel", closes == 1)
stock_panel = nil
for _ = 1, 1000 do step(b) end
check("the rules stay open past the first turn's time", windows[#windows].open)
held = { t = true }
step(b)
held = {}
check("T alone does nothing", windows[#windows].open and #windows == before + 1)
press()
check("Shift + T again closes them", not windows[#windows].open and closes == 1)
held = { shift = true, t = true }
for _ = 1, 5 do step(b) end
held = {}
step(b)
check("held down, Shift + T counts once", #windows == before + 2 and windows[#windows].open)
stock_panel = { x = 100, y = 200, w = 177, h = 159, open = true, opened = 1, cells = {} }
press()
check("over the open panel, Shift + T keeps the hidden rules and shuts the panel",
  #windows == before + 2 and windows[#windows].open and closes == 2)
stock_panel = nil

if failed > 0 then
  print(failed .. " Team17 check(s) failed")
  os.exit(1)
end
print("Team17 rules: all checks passed")
