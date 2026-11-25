local root = MOLE_SHOPPER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../mole_shopper/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function() return {PX_POSTURE={},PX_HANDS={"hand.png"}} end
local claims, launches, blasts, sounds, speakers, hook, frame = {}, {}, {}, {}, {}, nil, 1
local draws, ripples = {}, {}
wa = {
  math = {cos=math.cos, sin=math.sin},
  weapons = {replace=function(v) claims[#claims+1]=v end,
    data=function() return {clusters={bit={sprite=900}}} end,
    launch=function(v) launches[#launches+1]=v; return #launches+100 end},
  on = {draw=function(f) draws[#draws+1]=f end, missile_frame=function(v) hook=v end},
  view = {ripple=function(v) ripples[#ripples+1]=v end},
  actors = {spawn=function(spec)
    local a={spec=spec,dead=false}
    function a:remove() self.dead=true end
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
-- A stone ripples where it lands, once; the clouds never do.
local draw=draws[#draws]
hook{weapon="px.precipitator",phase="post",id=101,x=10,y=20,vx=1,vy=5}
hook{weapon="px.precipitator",phase="post",id=500,x=30,y=40,vx=2,vy=6}
hook{weapon="px.precipitator",phase="pre",id=501,x=0,y=0,vx=0,vy=0}
hook{weapon="px.golden_grenade",phase="post",id=502,x=0,y=0,vx=0,vy=0}
draw()
assert(#ripples==0, "a live stone does not ripple")
frame=3
draw()
assert(#ripples==1 and ripples[1].x==32 and ripples[1].y==46, "only the landed stone ripples")
draw()
assert(#ripples==1, "a stone ripples once")
frame=1
launches={}
require("weapons/golden_grenade").install{id="px.golden_grenade"}
local gold=claims[2]
assert(gold.wep=="weps/golden_grenade.wep" and gold.copy_from==nil, "PX's own record: blast and clusters")
assert(gold.missile==nil and gold.clusters==nil, "nothing overrides the record's firing")
assert(gold.cluster_sprite and gold.sprite)
-- The grenade and its clusters are WA's: the script only draws.
hook{weapon="px.golden_grenade",phase="pre",id=77,sprite=1}
gold.on_explode{worm=w,missile=77,x=50,y=60}
hook{weapon="px.golden_grenade",phase="pre",id=78,sprite=900}
gold.on_explode{worm=w,missile=78,x=1,y=2}
assert(#launches==0 and #blasts==0 and #sounds==0, "no scripted secondaries, blasts or sounds")
-- A missile of another weapon is left alone.
hook{weapon="px.precipitator",phase="pre",id=79,sprite=900}
print("Golden Grenade record and Precipitator payload/aim/pose passed")
