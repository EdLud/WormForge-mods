local root = MOLE_SHOPPER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../mole_shopper/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function() return {PX_POSTURE={},PX_HANDS={"hand.png"}} end
local claims, launches, blasts, sounds, speakers, hook, frame = {}, {}, {}, {}, {}, nil, 1
wa = {
  math = {cos=math.cos, sin=math.sin},
  weapons = {replace=function(v) claims[#claims+1]=v end,
    data=function() return {clusters={bit={sprite=900}}} end,
    launch=function(v) launches[#launches+1]=v; return #launches+100 end},
  on = {draw=function() end, missile_frame=function(v) hook=v end},
  actors = {spawn=function(spec)
    local a={spec=spec,dead=false}
    function a:despawn() self.dead=true end
    speakers[#speakers+1]=a
    return a
  end},
  world = {frame=function() return frame end, blast=function(v) blasts[#blasts+1]=v end},
  sound = {play=function(w,s) sounds[#sounds+1]={w,s} end},
  random=function(a,b) assert(a==69 and b==71); return a end,
  log=function() end,
}
local w = {id=1,aim=.5,facing=1}
wa.worms = {all=function() return {w} end}
require("weapons/precipitator").install{id="px.precipitator"}
local gun=claims[1]
assert(gun.copy_from=="stock.minigun" and gun.gun.bullets==25)
assert(not gun.fires or gun.fires.subtype==nil, "inherit Minigun held and firing art")
local p=gun.projectile
assert(p.copy_from=="stock.grenade" and p.missile.explosion.power==0)
assert(p.missile.fuse==5000 and p.missile.gravity_pct==-1 and p.missile.countdown==0)
assert(p.clusters.count==1 and p.clusters.bit.explosion.power==18 and p.clusters.bit.explosion.push_pct==370)
assert(p.missile.trail.sprite:find("snow.png") and p.clusters.bit.trail.sprite:find("stone.png"))
for _,side in ipairs({-1,1}) do
  w.facing=side
  for _,aim in ipairs({0,.25,.5,.75,1}) do
    w.aim=aim
    gun.on_fire{worm=w,x=100,y=200}
    local shot=launches[#launches]
    assert(shot.weapon=="px.precipitator" and shot.owner==w and shot.x==100 and shot.y==200)
    assert(shot.vx==side*math.min(aim,1-aim)*20 and shot.vy==(.5-aim)*20)
  end
end
assert(#launches==10, "one native gun callback launches exactly one payload")
launches={}
require("weapons/golden_grenade").install{id="px.golden_grenade"}
local gold=claims[2]
assert(gold.copy_from=="stock.grenade" and gold.missile.burst=="nothing")
assert(gold.missile.explosion.power==0 and not gold.missile.explosion_sound.enabled)
hook{weapon="px.golden_grenade",phase="pre",id=77}
gold.on_explode{worm=w,missile=77,x=50,y=60}
assert(#blasts==1 and blasts[1].damage==90 and blasts[1].radius==184)
assert(blasts[1].push_pct==60 and blasts[1].terrain_radius==90)
assert(#launches==4 and #sounds==1)
assert(sounds[1][1]==speakers[1] and sounds[1][1]~=w, "audio must use the blast emitter, not the event owner")
assert(speakers[1].spec.x==50 and speakers[1].spec.y==60)
assert(speakers[1].spec.persist and speakers[1].spec.solid==false)
frame=150
speakers[1].spec.on(speakers[1])
assert(not speakers[1].dead)
frame=151
speakers[1].spec.on(speakers[1])
assert(speakers[1].dead, "the nonblocking sound emitter must expire")
for i,shot in ipairs(launches) do
  assert(shot.weapon=="px.golden_grenade" and shot.owner==w and shot.x==50 and shot.y==40)
  assert(shot.missile.sprite==900 and shot.missile.fuse==8000 and shot.missile.action=="none")
  local angle=(-97.5+(i-1)*5)*math.pi/180
  assert(math.abs(shot.vx-math.cos(angle)*10)<1e-9 and math.abs(shot.vy-math.sin(angle)*10)<1e-9)
end
gold.on_explode{worm=w,missile=101,x=1,y=2}
assert(#launches==4 and #blasts==2, "children never create a further generation")
assert(blasts[2].damage==60 and blasts[2].radius==124 and blasts[2].push_pct==100 and blasts[2].terrain_radius==60)
-- A child can hit terrain and burst inside its constructor, before launch returns an id.
local base=wa.weapons.launch
wa.weapons.launch=function(v)
  local id=base(v)
  gold.on_explode{worm=w,missile=id,x=v.x,y=v.y}
  return id
end
hook{weapon="px.golden_grenade",phase="pre",id=78}
gold.on_explode{worm=w,missile=78,x=50,y=60}
assert(#launches==8 and #blasts==7, "constructor-time child bursts must not recurse into more children")
-- If a launch is refused or errors, finish the callback rather than leaving a turn waiting forever.
wa.weapons.launch=function() return nil end
hook{weapon="px.golden_grenade",phase="pre",id=79}
gold.on_explode{worm=w,missile=79,x=50,y=60}
wa.weapons.launch=function() error("pool full") end
hook{weapon="px.golden_grenade",phase="pre",id=80}
gold.on_explode{worm=w,missile=80,x=50,y=60}
local before=#sounds
-- A secondary still has a sound emitter after its original owner was freed.
gold.on_explode{worm={id=0},missile=105,x=4,y=5}
assert(#sounds==before+1 and speakers[#speakers].spec.owner==w)
print("Golden blast/fan/stages/reentrancy/audio and Precipitator payload/aim/pose passed")
