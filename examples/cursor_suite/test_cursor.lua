-- Run from this bundle: lua test_cursor.lua
local sim, now, keys = false, 0, {}
local pointer = { x = 120, y = 80, down = false }
local claim, actors, fields, fires, worms, graves = nil, {}, {}, {}, {}, {}
local lines, hooks = {}, { turn_start = {}, turn_end = {}, hud = {} }
local function simulation(fn, ...)
  sim = true
  fn(...)
  sim = false
end
wa = {
  weapons = { replace = function(spec) assert(not claim); claim = spec end },
  cursor = { spawn = function(spec)
    assert(sim)
    local a = { x = spec.x, y = spec.y, spec = spec, dead = false }
    function a:despawn() assert(sim); self.dead = true end
    actors[#actors + 1] = a
    return a
  end },
  magnetism = { field = function(spec)
    assert(sim)
    function spec:remove() assert(sim and not self.removed); self.removed = true end
    fields[#fields + 1] = spec
    return spec
  end },
  world = {
    frame = function() assert(sim); return now end,
    pointer = function() assert(sim); return pointer end,
    keys = function() assert(sim); return keys end,
  },
  fire = { spawn = function(spec) assert(sim); fires[#fires + 1] = spec end },
  worms = { all = function() assert(sim); return worms end },
  graves = { all = function() assert(sim); return graves end },
  hud = { line = function(line) assert(not sim); lines[#lines + 1] = line end },
  fog = { set = function() error("Cursor must not change the profile's fog settings") end },
  on = {},
}
for event, handlers in pairs(hooks) do
  wa.on[event] = function(fn) handlers[#handlers + 1] = fn end
end
local component = dofile("weapon.lua")
assert(component.defaults.ammo.round_start == -1)
component.install{ id = "cursors.cursor" }
assert(claim.name == "Cursor" and claim.copy_from == "stock.teleport")
assert(claim.on_select.cursor and claim.eat_fire and claim.click_finish == false)
assert(claim.handling.ends_turn == false)
local caster = { id = 16, hp = 100, turn = true, weapon = "cursors.cursor" }
local function select()
  simulation(claim.on_select.on, { worm = caster, x = pointer.x, y = pointer.y })
  return actors[#actors]
end
local function tick(a, frame)
  now = frame or now + 1
  a.x, a.y = pointer.x, pointer.y
  simulation(a.spec.on, a)
end
local function click(x, y, worm)
  simulation(claim.on_click, { worm = worm or caster, x = x or pointer.x, y = y or pointer.y })
end
local function emit(event, ev)
  for _, fn in ipairs(hooks[event]) do
    if event == "hud" then fn() else simulation(fn, ev) end
  end
end
local a = select()
local function hud()
  emit("hud")
  return lines[#lines]
end
local function next_mode(name)
  keys.plus_key = false; tick(a)
  keys.plus_key = true; tick(a)
  assert(hud():find("Cursor: " .. name, 1, true), hud())
  keys.plus_key = false; tick(a)
end
assert(a.light.circle == 300 and a.light.shadow_cast and a.light.seen_by == "owner")
assert(not a.light.discover and a.light.cone.length == 0)
click()
assert(not a.dead and #actors == 1 and #fields == 0)
next_mode("Magnet attract")
local attract = fields[#fields]
assert(a.light == false and #actors == 1, "modes reuse one cursor and remove the light")
assert(attract.source == a and attract.range == 300 and attract.strength == 14000 and attract.max_force == 12)
assert(attract.polarity == "attract" and attract.softening == 10)
for digit = 1, 9 do
  keys.digit = digit; tick(a)
  assert(attract.strength == 14000 and attract.max_force == 12, "digits no longer set power")
end
keys.digit = nil
next_mode("Magnet repel")
local repel = fields[#fields]
assert(attract.removed and repel.polarity == "repel" and repel.softening == 5)
keys.plus_key = true
for _ = 1, 5 do tick(a) end
assert(repel.removed and hud():find("Revive"), "first press advances")
local field_count = #fields
for _ = 1, 5 do tick(a) end
assert(hud():find("Revive") and #fields == field_count, "holding + never repeats")
keys.plus_key = false; tick(a)

local function grave(x, y, id, refused)
  local g = { x = x, y = y, worm_id = id, calls = 0 }
  function g:revive(worm_id, health)
    assert(sim and worm_id == self.worm_id and health == 100)
    self.calls = self.calls + 1
    return not refused and { id = worm_id, hp = health } or nil
  end
  return g
end
local unlinked, far, near = grave(120, 80, 0), grave(130, 80, 32), grave(121, 80, 33)
graves = { unlinked, far, near }
click()
assert(near.calls == 1 and far.calls == 0 and unlinked.calls == 0)
click(200, 200)
assert(near.calls == 1)
graves = { grave(144, 80, 35, true), grave(144, 80, 36) }
click()
assert(graves[1].calls == 1 and graves[2].calls == 0, "24 px boundary, stable ties and refused revival")
click(119, 80)
click(120, 80, { id = 32 })
assert(graves[1].calls == 1, "outside radius and foreign clicks are ignored")
next_mode("Freeze")
local function worm(x, y, hp)
  local w = { x = x, y = y, hp = hp, calls = 0, hurts = 0 }
  function w:freeze() assert(sim); self.calls = self.calls + 1 end
  function w:hurt(amount)
    assert(sim and amount == 10)
    self.hurts = self.hurts + 1
    self.hp = math.max(0, self.hp - amount)
  end
  return w
end
worms = { worm(120, 80, 0), worm(130, 80, 100), worm(121, 80, 50) }
click()
assert(worms[1].calls == 0 and worms[2].calls == 0 and worms[3].calls == 1)
click(200, 200)
assert(worms[3].calls == 1)
caster.x, caster.y, caster.calls = 120, 80, 0
function caster:freeze() assert(sim); self.calls = self.calls + 1 end
worms = { caster }; click()
assert(caster.calls == 1, "self and friendly freeze allowed")

pointer.down = true
next_mode("Fire")
for _ = 1, 10 do tick(a) end
assert(#fires == 0, "a held click cannot fire when entering Fire mode")
pointer.down = false; tick(a)
pointer.down = true
local start = now + 1
for frame = start, start + 49 do tick(a, frame); tick(a, frame) end
assert(#fires == 25, "25 flames per second, never per rendering/update call")
local colours = {}
for _, f in ipairs(fires) do
  assert(f.owner == caster and f.x == 120 and f.y == 74)
  assert(f.count == 0 and f.damage == 0 and f.duration == 4000)
  colours[f.tint] = true
end
local n = 0
for _ in pairs(colours) do n = n + 1 end
assert(n == 7)
pointer.down = false; tick(a)
assert(#fires == 25)
pointer.x, pointer.y, pointer.down = 300, 200, true
tick(a)
assert(#fires == 26 and fires[26].x == 300 and fires[26].y == 194)
next_mode("Hurt")
worms = { worm(300, 200, 0), worm(310, 200, 30), worm(301, 200, 6) }
for _ = 1, 10 do tick(a) end
assert(#fires == 26 and worms[3].hurts == 0, "Hurt stops fire and damages only on click")
click()
assert(worms[1].hurts == 0 and worms[2].hurts == 0 and worms[3].hurts == 1)
assert(worms[3].hp == 0, "Hurt permits lethal damage through the ordinary hurt call")
click()
assert(worms[2].hp == 20 and worms[2].hurts == 1 and worms[3].hurts == 1, "skip dead targets")
click(400, 300)
click(300, 200, { id = 99 })
assert(worms[2].hurts == 1, "outside radius and foreign clicks cannot hurt")
caster.x, caster.y, caster.hurts = 300, 200, 0
caster.hurt = worms[2].hurt
worms = { caster }; click()
assert(caster.hp == 90 and caster.hurts == 1, "self damage uses the same ordinary hurt call")
next_mode("Light")
assert(a.light.circle == 300 and #fires == 26, "leaving Fire stops spraying even while held")

-- Reselect Fire with a fresh press before 50 ms: it still waits 3 frames.
for _, name in ipairs({ "Magnet attract", "Magnet repel", "Revive", "Freeze", "Fire" }) do next_mode(name) end
local old = a
pointer.down = false
a = select()
assert(old.dead and #actors == 2)
local selected_at, before = now, #fires
tick(a, selected_at + 1)
pointer.down = true; tick(a, selected_at + 2)
assert(#fires == before)
tick(a, selected_at + 3)
assert(#fires == before + 1, "selection grace persists after consolidation")

-- Mode ownership, held-key selection, and cleanup across every effect.
local other = { id = 32, hp = 100, turn = true, weapon = "cursors.cursor" }
caster = other; a = select()
assert(a.light.circle == 300 and hud():find("Light"), "another worm starts with its own mode")
for _, name in ipairs({ "Magnet attract", "Magnet repel", "Revive", "Freeze", "Fire", "Hurt", "Light" }) do
  next_mode(name)
  local last_field = fields[#fields]
  local prior = a
  keys.plus_key = true
  a = select(); tick(a)
  assert(prior.dead and hud():find(name, 1, true), "reselect remembers mode without advancing held +")
  if last_field and not (name == "Light") then assert(last_field.removed) end
  keys.plus_key = false
  caster.weapon = "stock.skip_go"; tick(a)
  assert(a.dead and a.light == false)
  local lines_before = #lines; emit("hud"); assert(#lines == lines_before)
  local count = #actors
  emit("turn_start", { worm = caster }); assert(#actors == count)
  caster.weapon = "cursors.cursor"
  emit("turn_start", { worm = caster }); a = actors[#actors]
  assert(not a.dead and a.x == pointer.x and a.y == pointer.y)
  emit("turn_end", { worm = caster }); emit("turn_end", { worm = caster })
  assert(a.dead and a.light == false)
  click()
  a = select(); caster.hp = 0; tick(a)
  assert(a.dead and a.light == false)
  count = #actors; select(); assert(#actors == count)
  caster.hp, caster.turn = 100, false
  select(); assert(#actors == count)
  caster.turn = true; a = select()
end
for _, f in ipairs(fields) do assert(f.removed, "no orphaned magnetic fields") end
print("PASS: one Cursor, seven modes, + edges, fixed magnet strength, light/field cleanup, revive/freeze/hurt, guarded rainbow fire and lifecycle")
