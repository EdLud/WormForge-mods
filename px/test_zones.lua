-- lua mods/px/test_zones.lua (or the embedded Lua-host test).
local root = HIGHLANDER_ROOT or "mods/px/"
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
local blasts, sim_random, asset_loads
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
  for _, name in ipairs({"lib/px_zone", "lib/px_zone_fx", "lib/px_health_zone", "lib/px_blast_zone",
    "weapons/health_zone", "weapons/blast_zone"}) do package.loaded[name] = nil end
  hooks, actors, claims, draws, nearby, worms, keys, assets = {}, {}, {}, {}, {}, {}, {}, {}
  blasts, sim_random, asset_loads = 0, 0, 0
  wa = {
    depth = { EFFECTS = 12, WORMS = 16, OBJECTS = 20 },
    math = { sin = math.sin, cos = math.cos, atan = math.atan },
    msg = { FIRE_WEAPON = 1, FRAME_FINISH = 2 }, on = {},
    world = { wind = function() return 0 end, gravity = function() return 1/8 end,
      water = function() return 1000 end, keys = function() return keys end,
      electrical_nearby = function() return nearby end },
    worms = { all = function() return worms end },
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
      local a = { x = s.x, y = s.y, on = s.on, owner = s.owner }
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
  function w:hurt(n) self.hp=self.hp-n end
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
keys.minus_key=true; event("worm_message",w,wa.msg.FRAME_FINISH)
health.on_explode({x=100,y=100}); w.hp=2
frames(50); assert(w.hp==1); frames(50); assert(w.hp==1)
assert(draw()[1].sprite:match("fallout"), "damage mode uses PX's fallout strip")
health = reset(30)
local grave = {kind="grave",id=2,x=100,y=100,worm_id=17}
function grave:revive(id,hp) assert(id==17 and hp==1); self.revived=true end
nearby={grave}; health.on_explode({x=100,y=100}); frames(50); assert(grave.revived)

-- Original animation sheets, phase timing, additive passes, shared asset load,
-- cosmetic particles and cleanup all run through the real port entry points.
local blast
health,blast = reset(60,3,true); w=worm()
assert(asset_loads==1, "both components share the FX sheets")
health.on_explode({x=100,y=100})
frames(25); local q=draw()[1]
assert(q.sprite:match("mcrate0") and q.frame==30 and q.depth==17)
assert(math.abs(q.points[2][1]-q.points[1][1])==60)
blast.on_explode({x=300,y=100}); frames(5)
local exp = {}
for _, item in ipairs(draw()) do if item.sprite:match("blast_zone/exp") then exp[#exp+1]=item end end
assert(#exp==9 and exp[1].frame==1 and exp[1].blend=="add")
-- Trigger once; repeated frames and cosmetic draws must not retrigger a blast.
w.x=300; frames(5); assert(blasts==1); frames(50); draw(); draw(); assert(blasts==1)
event("turn_end"); frames(360); event("turn_start"); frames(5); assert(blasts==2)
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
