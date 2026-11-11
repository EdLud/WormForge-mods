-- lua mods/tests/px/test_zones.lua (or the embedded Lua-host test).
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/px_sprite_builder"] = function()
  local sdk = root:gsub("px/$", "sdk/")
  local env = setmetatable({ require = function(name)
    assert(name == "holds")
    return assert(loadfile(sdk .. "holds.lua"))()
  end }, { __index = _G })
  return assert(loadfile(sdk .. "px_sprite_builder.lua", "t", env))()
end
local hooks, actors, claims, draws, nearby, worms, keys, assets
local blasts, sim_random, asset_loads, top_messages, crate_list, fog_on, shade_at
local function event(name, ...)
  for _, f in ipairs(hooks[name] or {}) do f(...) end
end
local function frames(n)
  for _ = 1, n do
    local count = #actors
    for i = 1, count do
      local a = actors[i]
      if not a.dead then
        local f = type(a.on) == "table" and a.on.frame or a.on
        if f then f(a) end
      end
    end
  end
end
local function draw()
  draws = {}; event("draw"); return draws
end
local function reset(rate, turns, both)
  for _, name in ipairs({"lib/weapon_hint", "wf-lib/tooltip", "lib/px_zone", "lib/px_zone_fx", "lib/px_health_zone", "lib/px_blast_zone",
    "lib/px_spot_hider", "weapons/health_zone", "weapons/blast_zone", "weapons/spot_hider"}) do package.loaded[name] = nil end
  hooks, actors, claims, draws, nearby, worms, keys, assets = {}, {}, {}, {}, {}, {}, {}, {}
  blasts, sim_random, asset_loads, top_messages, crate_list = 0, 0, 0, {}, {}
  wa = {
    depth = { EFFECTS = 12, WORMS = 16, OBJECTS = 20 },
    math = { sin = math.sin, cos = math.cos, atan = math.atan },
    hud = {message_top = function(text, options)
      assert(options.to == "coalition" and options.alliance == 2)
      assert(#text <= 127)
      top_messages[#top_messages+1] = text
      return true
    end},
    msg = { FIRE_WEAPON = 1, FRAME_FINISH = 2 }, on = {},
    -- Only the read: a weapon never turns fog on or changes its settings.
    fog = { enabled = function() return fog_on end,
      shade = function(x, y) return shade_at and shade_at(x, y) or 0 end },
    log = function() end,
    world = { wind = function() return 0 end, gravity = function() return 1/8 end,
      water = function() return 1000 end, keys = function() return keys end,
      electrical_nearby = function() return nearby end },
    worms = { all = function() return worms end },
    crates = { all = function(f)
      assert(f and f.near, "crates are listed near the zone")
      return crate_list
    end },
    random = function(lo) sim_random = sim_random + 1; return lo end,
    assets = { load = function(s)
      asset_loads = asset_loads + 1
      for _, path in ipairs(s.sprites) do assets[path] = true end
    end },
    weapons = { replace = function(s)
      claims[#claims+1] = s
      for _, path in ipairs(s.sprites) do assets[path] = true end
    end },
    actors = { spawn = function(s)
      local a = { x = s.x, y = s.y, on = s.on, owner = s.owner, sprite = s.sprite, solid = s.solid }
      function a:despawn() self.dead = true end
      function a:explode(e) assert(e.damage == 30 and e.id == 30); blasts = blasts + 1 end
      function a:gfx() end
      function a:frame() end
      actors[#actors+1] = a; return a
    end },
    draw = { quad = function(q)
      assert(assets[q.sprite], "quad sheet must be loaded: " .. q.sprite)
      local copy = {sprite=q.sprite,frame=q.frame,color=q.color,depth=q.depth,blend=q.blend,points={}}
      for i, p in ipairs(q.points) do copy.points[i] = {p[1],p[2]} end
      draws[#draws+1] = copy
    end },
  }
  for _, name in ipairs({ "turn_start", "turn_end", "draw", "worm_message", "missile_frame" }) do
    wa.on[name] = function(f)
      hooks[name] = hooks[name] or {}; hooks[name][#hooks[name]+1] = f
    end
  end
  dofile(root .. "../tests/tooltip_mock.lua")(root)
  require("weapons/health_zone").install({ id = "px.health_zone", option = function(k)
    return ({ turns = turns or 3, healing_per_minute = rate or 60 })[k]
  end })
  if both then require("weapons/blast_zone").install({id="px.blast_zone"}) end
  return claims[1], claims[2]
end
local function worm(x)
  local w = { kind="worm", id=1, x=x or 100, y=100, vx=0, vy=0, hp=100,
    weapon="px.health_zone", turn=true, aiming=false, aim=0.5, facing=1, alliance=2 }
  function w:heal(n) assert(math.type(n)=="integer"); self.hp=self.hp+n end
  -- The zone's damage is a drain, not a hit: a hit a second on the turn's
  -- worm kept WA's damage pause up, and the turn never resumed.
  function w:hurt() error("zone damage must not be a hit") end
  function w:reduce_health(n)
    assert(math.type(n)=="integer")
    if self.hp <= n then return false end
    self.hp=self.hp-n; return true
  end
  worms, nearby = {w}, {w}; return w
end

-- The planting turn must not consume any of the configured subsequent turns.
for _, duration in ipairs({1,3,20}) do
  local health = reset(60,duration)
  local w = worm()
  event("turn_start"); event("worm_message",w,wa.msg.FIRE_WEAPON)
  health.on_explode({x=100,y=100})
  local zone_actor = actors[1]
  event("turn_end"); frames(1)
  for turn = 1, duration do
    event("turn_start"); frames(50)
    assert(w.hp==100+turn, "zone must heal during subsequent turn " .. turn)
    event("turn_end"); frames(1)
    assert(not zone_actor.dead, "visual fade must outlive the payload")
  end
  local hp = w.hp
  event("turn_start"); frames(50)
  assert(w.hp==hp, "expired zone must never heal on the following turn")
  frames(150); assert(zone_actor.dead and #draw()==0, "fade must clean up completely")
end

-- Fractional HP/sec is represented without fractional native health or drift.
for _, rate in ipairs({1,30,60,90,60000}) do
  local health = reset(rate,20); local w = worm()
  health.on_explode({x=100,y=100}); frames(3000)
  assert(w.hp==100+rate, "exact HP/min accumulation at rate " .. rate)
end
local health = reset(30)
local w = worm(500)
health.on_explode({x=100,y=100}); frames(3000)
w.x=100; frames(50); assert(w.hp==100, "empty time must not bank healing")
frames(50); assert(w.hp==101)

-- Mode, resurrection and nonlethal damage keep their existing gameplay.
health = reset(60000); w = worm()
keys.plus_key=true; event("worm_message",w,wa.msg.FRAME_FINISH)
health.on_explode({x=100,y=100}); w.hp=2
frames(50); assert(w.hp==1); frames(50); assert(w.hp==1)
assert(draw()[1].sprite:match("fallout"), "damage mode uses PX's fallout strip")
health = reset(30)
local grave = {kind="grave",id=2,x=100,y=100,worm_id=17}
function grave:revive(id,hp) assert(id==17 and hp==1); self.revived=true end
nearby={grave}; health.on_explode({x=100,y=100}); frames(50); assert(grave.revived)
-- Graves stacked as near: the one for the lower worm id comes back first on
-- every peer, whatever order their addresses (`id`) and uids put them in.
for _, ids in ipairs({{0x2000, 0x1000}, {0x1000, 0x2000}}) do
  health = reset(30)
  local first
  local function stacked(id, worm_id)
    local g = {kind="grave",id=id,uid=id,x=100,y=100,worm_id=worm_id}
    function g:revive(wid) first = first or wid end
    return g
  end
  nearby={stacked(ids[1],17), stacked(ids[2],34)}
  health.on_explode({x=100,y=100}); frames(50)
  assert(first==17, "stacked graves: the lower worm id comes back first, not the lower address")
end

-- Original animation sheets, phase timing, additive passes, shared asset load,
-- cosmetic particles and cleanup all run through the real port entry points.
local blast
health,blast = reset(60,3,true); w=worm()
assert(asset_loads==1, "both components share the FX sheets")
health.on_explode({x=100,y=100})
frames(25); local q=draw()[1]
assert(q.sprite:match("mcrate0") and q.frame==30 and q.depth==17)
assert(math.abs(q.points[2][1]-q.points[1][1])==60)
-- Upright, as the sheet is stored: its first corner is the top left.
assert(q.points[1][1] < q.points[2][1] and q.points[1][2] < q.points[4][2], "the zone art is upright")
blast.on_explode({x=300,y=100}); frames(5)
local exp = {}
for _, item in ipairs(draw()) do if item.sprite:match("blast_zone/exp") then exp[#exp+1]=item end end
assert(#exp==9 and exp[1].frame==1 and exp[1].blend=="add")
-- Trigger once; repeated frames and cosmetic draws must not retrigger a blast.
w.x=300; frames(5); assert(blasts==1); frames(50); draw(); draw(); assert(blasts==1)
event("turn_end"); frames(360); event("turn_start"); frames(5); assert(blasts==2)
-- A crate sets the zone off whenever it touches it, asleep or spent, each
-- crate once: crates drop at a turn's start, while the zone sleeps.
local function crate(id, x, y)
  local c = { kind = "crate", id = id, uid = id, x = x, y = y, hits = 0 }
  function c:hit(d) assert(d == 30); self.hits = self.hits + 1 end
  return c
end
local c1 = crate(7, 300, 100 - 22.5 - 9)
crate_list = { c1 }; frames(1); assert(blasts==3 and c1.hits==1, "a spent zone still blows a crate up")
frames(50); assert(blasts==3 and c1.hits==1, "each crate once")
w.x=900; event("turn_end"); frames(360)
local c2 = crate(8, 300 + 22.5 + 10, 100)
crate_list = { c2 }; frames(5); assert(blasts==3 and c2.hits==0, "a crate clear of the box is left alone")
c2.x = 300; frames(1); assert(blasts==4 and c2.hits==1, "a sleeping zone blows a falling crate up")
local c3, c4 = crate(9, 300, 100), crate(10, 305, 100)
crate_list = { c3, c4 }; frames(1); assert(blasts==5 and c3.hits==1 and c4.hits==0, "one crate a frame")
frames(1); assert(blasts==6 and c4.hits==1)
crate_list = {}
assert(sim_random==0, "effects must not consume gameplay RNG")
health = reset(60); w=worm(); w.aiming=true
event("worm_message",w,wa.msg.FRAME_FINISH)
assert(actors[1].owner==w, "particle updater needs the aiming worm as its explicit owner")
assert(#draw()==1 and draws[1].sprite:match("mcrate0"))
frames(25); assert(#draw()==0)
w.aiming=false; event("worm_message",w,wa.msg.FRAME_FINISH); assert(#draw()==0)
for _, weapon in ipairs({"px.health_zone","px.blast_zone"}) do
  reset(60,3,true)
  w=worm(); w.weapon=weapon
  for shot = 1, 6 do
    local missile={weapon=weapon,phase="pre",id=shot,x=100,y=100,vx=1,vy=0}
    event("missile_frame",missile); assert(#draw()==0)
    missile.phase="post"
    -- Enough emissions to fill the cap if the updater fails to age particles.
    for _ = 1, 100 do event("missile_frame",missile); frames(1) end
    assert(#draw()>0, "later shots must still have trails")
    for _, a in ipairs(actors) do assert(a.owner==w, "flight actors need an explicit owner") end
    assert(sim_random==0)
    frames(45); assert(#draw()==0, "trails must expire after every shot")
    for _, a in ipairs(actors) do assert(a.dead, "idle particle updater must clean up") end
  end
end
print("Zones: subsequent-turn lifetime, HP/min accumulation, original art, particles and gameplay regression checks passed")

-- Tooltips follow the selected mode once, with the planting worm's coalition.
reset(60,3,true)
local hint_worm = worm()
local function hint_frames(n)
  for _=1,n do event("worm_message",hint_worm,wa.msg.FRAME_FINISH) end
end
hint_frames(3)
assert(#top_messages==1 and top_messages[1]:find("HEALING",1,true))
hint_frames(10); assert(#top_messages==1)
-- + switches the mode once per press, however long it is held, though
-- every other worm gets its frame too.
keys.plus_key=true
local other = { kind="worm", id=2, x=300, y=100, hp=100, weapon="px.health_zone", turn=false,
  aiming=false, aim=0.5, facing=1, alliance=2 }
for _=1,5 do event("worm_message",other,wa.msg.FRAME_FINISH); hint_frames(1) end
assert(#top_messages==2 and top_messages[2]:find("DAMAGING",1,true), "held + switches once")
keys.plus_key=false; hint_frames(3); assert(#top_messages==2)
keys.plus_key=true; hint_frames(3)
assert(#top_messages==3 and top_messages[3]:find("HEALING",1,true))
keys.plus_key=false; hint_worm.weapon="px.blast_zone"; hint_frames(3)
assert(#top_messages==4 and top_messages[4]:find("Blast Zone:",1,true))
keys.digit=5; hint_frames(3)
assert(#top_messages==5 and top_messages[5]:find("6 turns",1,true))
hint_frames(10); assert(#top_messages==5)
print("Zone tooltips: coalition, selection, mode/duration changes and no repeated messages passed")

-- Spot Hider: the shadow look's spreading darkness, or PX's flat mask.
local function spot_hider(options, placed)
  reset(); claims = {}
  require("weapons/spot_hider").install({ id = "px.spot_hider",
    weapons = { ["px.spot_hider"] = placed ~= false and {} or nil },
    option = function(k) return options[k] end })
  return claims[1]
end
local function fire(claim)
  local shooter = worm(); shooter.weapon = "px.spot_hider"
  event("worm_message", shooter, wa.msg.FIRE_WEAPON)
  local missile = { weapon = "px.spot_hider", phase = "pre", id = 1, x = 100, y = 100, vx = 1, vy = 0 }
  event("missile_frame", missile); missile.phase = "post"; event("missile_frame", missile)
  assert(actors[#actors].sprite == "sprites/spot_hider/pulse.png", "the pulse flies")
  claim.on_explode({ x = 350, y = 200 })
  local a = actors[#actors]
  assert(a.x == 350 and a.y == 200 and a.sprite == false)
  assert(a.solid == false, "a blast must not knock the zone (and its darkness) away")
  return a, shooter
end
local function four_turns()
  for turn = 1, 4 do
    event("turn_end")
    if turn < 4 then frames(1); event("turn_start"); frames(50) end
  end
end

-- PX's mask: drawn over the worms and the land, four turns, then the fade.
do
  local claim = spot_hider({ look = "mask" })
  assert(claim.wep == "weps/spot_hider_wep.wep" and claim.handling.ends_turn)
  assert(claim.hold.sheet == "sprites/spot_hider/pulse.png" and claim.hold.frames == 1)
  assert(#claim.sprites == 2 and claim.sprites[2] == "sprites/spot_hider/mask.png")
  local a = fire(claim)
  local function mask(alpha)
    local d = draw()
    assert(#d == 1 and d[1].sprite == "sprites/spot_hider/mask.png" and d[1].color == alpha << 24)
    assert(d[1].blend == "alpha" and d[1].depth == wa.depth.EFFECTS)
    assert(d[1].points[2][1] - d[1].points[1][1] == 512, "PX's 4x mask")
  end
  mask(100); four_turns(); mask(100)
  assert(a.light == nil, "the mask look casts nothing")
  frames(375); mask(50)
  frames(375); assert(a.dead and #draw() == 0, "gone after the fade")
end

-- The shadow look: a darkness without fog that spreads out and fades.
for _, hides_for in ipairs({ "everyone", "enemies" }) do
  local claim = spot_hider({ look = "shadow", hides_for = hides_for, spread_seconds = 4 })
  assert(#claim.sprites == 1, "no mask sheet in the shadow look")
  local a, shooter = fire(claim)
  assert(a.owner == shooter, "the darkness belongs to the shooter's side")
  local function light(circle, strength, own)
    local l = assert(a.light)
    assert(l.mode == "dark" and l.reach == 256 and l.cone.length == 0 and l.without_fog == true)
    assert(l.shadow_cast == true and l.seen_by == "everyone")
    assert(l.into_terrain.depth == 8 and l.into_terrain.falloff == 8, "on into the terrain")
    assert(l.fill == true, "it fills the air, round corners")
    assert(l.circle == circle, "circle " .. tostring(l.circle) .. ", expected " .. circle)
    assert(l.strength == strength and l.owner_strength == own)
  end
  local own = hides_for == "enemies" and 128 or nil
  light(0, 255, own)
  frames(100); light(128, 255, own)
  frames(100); light(256, 255, own)
  assert(#draw() == 0, "the shadow look draws no quad: the engine draws the darkness")
  four_turns(); light(256, 255, own)
  frames(375); light(256, 128, own and 64)
  frames(375); assert(a.dead, "the darkness goes with its object")
end
-- A worm touching the darkness, as this machine sees it, has WA's HUD over
-- it hidden; out of it, or once the darkness is gone, it comes back.
do
  local claim = spot_hider({ look = "shadow" })
  fire(claim)
  local function at(x, y) return { id = x, x = x, y = y } end
  local inside, edge, outside = at(350, 200), at(395, 200), at(600, 200)
  worms = { inside, edge, outside }
  -- Full darkness within 40 px of the impact, half of it (the shooter's
  -- side, hides for enemies) from there to 60.
  shade_at = function(x, y)
    local d = math.sqrt((x - 350) ^ 2 + (y - 200) ^ 2)
    return d <= 40 and 255 or d <= 60 and 128 or 0
  end
  draw()
  local HUD = { labels = true, arrow = true, weapon = true, aim = true }
  local function hides(w) return type(w.hide_hud) == "table" and w.hide_hud.labels and w.hide_hud.arrow
    and w.hide_hud.weapon and w.hide_hud.aim end
  assert(hides(inside), "a worm in the dark has its HUD hidden")
  assert(hides(edge), "touching it with an edge is enough")
  assert(outside.hide_hud == nil, "a worm in the light is left alone")
  edge.x = 405; draw()
  assert(edge.hide_hud == false, "half darkness (the shooter's side) shows it again")
  four_turns(); frames(750); draw()
  assert(inside.hide_hud == false, "shown again once the darkness is gone")
  shade_at = nil
  worms = {}
  local mask = spot_hider({ look = "mask" }); fire(mask)
  worms = { at(350, 200) }; draw()
  assert(worms[1].hide_hud == nil, "PX's mask look hides no HUD")
end

-- No spread: full size at once.
local a = fire(spot_hider({ look = "shadow", spread_seconds = 0 }))
frames(1); assert(a.light.circle == 256)
assert(spot_hider({}, false) == nil, "an unplaced Spot Hider registers nothing")
assert(sim_random == 0)
print("Spot Hider: PX's mask and its fade; the shadow's spread, fade, owner and hides-for passed")

-- The radius option: as much darkness as a circle that size.
do
  local a = fire(spot_hider({ look = "shadow", radius = 120 }))
  frames(300)
  local l = assert(a.light)
  assert(l.reach == 120 and l.circle == 120 and l.fill == true, "the radius sets the fill's size")
end
