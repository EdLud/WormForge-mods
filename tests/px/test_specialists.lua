local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path
local classes = require("scheme/specialists_data").classes
local hooks, worms, inventory, cooldowns, placed, endings, draws, log
local function emit(name, ...)
  for _, f in ipairs(hooks[name] or {}) do f(...) end
end
local function select(worm)
  for _, w in ipairs(worms) do w.turn = false end
  worm.turn = true
  emit("turn_start", {worm=worm})
end
local function release(worm, id)
  worm.weapon = id
  emit("worm_message", worm, wa.msg.WEAPON_RELEASED)
end
local function add_worm(team, index, alliance)
  local w = { id=team*16+index, team=team, ammo_group=team, alliance=alliance or 0,
    hp=100, x=0, y=0, state="resting", turn=false, name="Original" }
  inventory[team], cooldowns[team] = inventory[team] or {}, cooldowns[team] or {}
  function w:heal(n) self.hp = self.hp + n end
  function w:ammo(id, change)
    assert(placed[id], "unplaced ammo write: " .. id)
    if change then
      assert(change.keep_delay == true, "class refresh must preserve delay")
      inventory[self.ammo_group][id] = change.set
    end
    return inventory[self.ammo_group][id] or 0
  end
  function w:delay(id, n)
    assert(placed[id], "unplaced delay access: " .. id)
    if n ~= nil then cooldowns[self.ammo_group][id] = n end
    return cooldowns[self.ammo_group][id] or 0
  end
  worms[#worms+1] = w
  return w
end
local function install(subset)
  hooks, worms, inventory, cooldowns, placed, endings, draws, log = {}, {}, {}, {}, {}, {}, {}, {}
  if subset then
    for _, id in ipairs(subset) do placed[id] = {} end
  else
    for _, class in ipairs(classes) do
      for _, list in ipairs({class.weapons, class.survivor}) do
        for _, id in ipairs(list) do placed[id] = {} end
      end
    end
  end
  placed["stock.jet_pack"], placed["stock.skip_go"] = {}, {}
  wa = {
    msg = {TURN_STARTED=56, WEAPON_RELEASED=73, FRAME_FINISH=2}, on = {},
    sorted = function(t)
      local keys = {}; for k in pairs(t) do keys[#keys+1] = k end
      table.sort(keys); return keys
    end,
    worms = {all=function() return worms end},
    assets = {load=function(s) assert(s.sprites[1] == "sprites/specialists/glow.png") end},
    weapons = {data=function(id) return {handling={ends_turn=endings[id] or false}} end},
    draw = {quad=function(q) draws[#draws+1] = q end}, depth = {EFFECTS=12},
    log = function(s) log[#log+1] = s end,
  }
  for _, name in ipairs({"turn_start", "worm_message", "hurt", "draw"}) do
    wa.on[name] = function(f, filter)
      hooks[name] = hooks[name] or {}
      if filter then
        local accepted = {}; for _, msg in ipairs(filter.msgs) do accepted[msg] = true end
        hooks[name][#hooks[name]+1] = function(w, msg) if accepted[msg] then f(w, msg) end end
      else hooks[name][#hooks[name]+1] = f end
    end
  end
  local ctx = {weapons=placed, selected=function() return false end}
  require("scheme/specialists_rules").install(ctx)
  for i=1,5 do add_worm(1,i) end
  return ctx
end
install()
for i, class in ipairs(classes) do
  select(worms[i])
  assert(worms[i].name == class.name and worms[i].hp == class.hp)
  local expected = {}; for _, id in ipairs(class.weapons) do expected[id] = true end
  for id, amount in pairs(inventory[1]) do
    assert(amount == (expected[id] and -1 or 0), class.name .. ": " .. id)
  end
end
local soldier, gunner, engineer, ninja, medic = table.unpack(worms)
soldier.hp = 100
soldier:delay("stock.dynamite",3) -- Initial profile/native delay.
inventory[1]["stock.jet_pack"] = 2
select(soldier); select(engineer); select(soldier)
assert(soldier.hp == 100 and soldier:delay("stock.dynamite") == 3)
assert(inventory[1]["stock.jet_pack"] == 2, "non-class pickups survive switching")
release(soldier,"stock.bazooka")
assert(soldier:delay("stock.bazooka") == 1)
select(ninja); select(soldier)
assert(soldier:delay("stock.bazooka") == 1, "Tab cannot unlock a shot")
-- Simulate native upkeep at a real turn boundary; Lua must not decrement again.
soldier:delay("stock.bazooka",0); soldier:delay("stock.dynamite",2)
emit("worm_message",soldier,wa.msg.TURN_STARTED)
assert(soldier:delay("stock.bazooka") == 0 and soldier:delay("stock.dynamite") == 2)
-- An explicit positive cooldown takes precedence over a turn-ending record.
endings["stock.teleport"] = true
select(medic); release(medic,"stock.teleport")
assert(medic:delay("stock.teleport") == 5)
-- Multi-shot resupply keeps the cooldown without force-equipping/cancelling.
release(medic,"px.real_shotgun")
assert(medic:delay("px.real_shotgun") == 1 and medic:ammo("px.real_shotgun") == -1)
-- Restore only locks created by this feature, including non-class inventory.
endings["stock.skip_go"] = true
release(medic,"stock.skip_go")
assert(medic:delay("stock.skip_go") == -1)
medic:delay("px.electromagnet",-1) -- An unrelated permanent profile lock.
select(soldier)
assert(soldier:delay("stock.skip_go") == -1)
emit("worm_message",soldier,wa.msg.TURN_STARTED)
assert(soldier:delay("stock.skip_go") == 0 and soldier:delay("px.electromagnet") == -1)
select(ninja); ninja.state = "roping"
emit("worm_message",ninja,wa.msg.FRAME_FINISH)
assert(ninja:delay("stock.ninja_rope") == 1)
ninja.state, ninja.weapon = "prefiring", "px.jump"
emit("worm_message",ninja,wa.msg.FRAME_FINISH)
assert(ninja:delay("px.jump") == 1)
select(medic); medic.state = "parachuting"; medic:delay("stock.parachute",-1)
emit("worm_message",medic,wa.msg.FRAME_FINISH)
assert(medic:delay("stock.parachute") == 0)
-- Only poison POST on a living Medic heals, once per native handoff, not Tab.
local ally = add_worm(2,1,0)
local enemy = add_worm(3,1,1)
for _, w in ipairs({ally,enemy}) do emit("worm_message",w,wa.msg.FRAME_FINISH) end
soldier.hp, soldier.x, soldier.y = 150, 60, 80 -- Exactly 100 pixels.
gunner.hp, gunner.x = 176, 0 -- Above class threshold, even though below Medic.
engineer.hp, engineer.x = 140, 101 -- Outside aura.
ninja.hp, ninja.x = 0, 0
ally.hp, enemy.hp, medic.hp = 120, 120, 200
select(medic); select(soldier); select(medic)
assert(soldier.hp == 150 and ally.hp == 120, "Tab must not heal")
emit("hurt",{worm=medic,phase="pre",kind="poison",lost=0})
emit("hurt",{worm=soldier,phase="post",kind="poison",lost=0})
emit("hurt",{worm=medic,phase="post",kind="hit",lost=10})
assert(soldier.hp == 150 and ally.hp == 120)
emit("hurt",{worm=medic,phase="post",kind="poison",lost=0})
assert(soldier.hp == 175 and ally.hp == 145, "includes allied teams and source overshoot")
assert(gunner.hp == 176 and engineer.hp == 140 and ninja.hp == 0 and enemy.hp == 120)
assert(medic.hp == 200, "no self healing")
emit("hurt",{worm=medic,phase="post",kind="poison",lost=0})
assert(soldier.hp == 175, "no further healing above class threshold")
emit("draw")
assert(#draws == 1 and draws[1].visibility == medic and draws[1].sprite)
-- Survivor bonuses use own team, not all allied teams; select refreshes them.
for _, w in ipairs({soldier,engineer,medic}) do w.hp = 0 end
select(gunner)
assert(gunner:ammo("stock.banana_bomb") == -1)
soldier.hp = 150
select(gunner)
assert(gunner:ammo("stock.banana_bomb") == 0)
-- No future/missing component may reach a native ammo/delay API.
local ctx = install({"stock.bazooka", "px.sentry_gun", "stock.parachute"})
for _, w in ipairs(worms) do select(w) end
release(worms[1],"stock.bazooka")
local extra = add_worm(1,6)
select(extra); emit("worm_message",extra,wa.msg.FRAME_FINISH)
assert(#log == 1 and extra.name == "Original")
ctx.selected = function(id) return id == "hl.rules" end
assert(not pcall(function() require("scheme/specialists_rules").install(ctx) end))
print("Specialists class, cooldown, Medic and pickup checks passed")
