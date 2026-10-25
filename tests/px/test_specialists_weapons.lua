local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function() return {PX_POSTURE={},PX_HANDS={"hand.png"}} end
local tele = require("weapons/tele_arrow").definition
local dynamite = require("weapons/thrown_dynamite")
local gatling = require("weapons/gatling_gun").definition
assert(gatling.copy_from == "stock.minigun" and gatling.gun.bullets == 45)
assert(gatling.gun.burst_size == 2 and gatling.gun.shot_interval_ms == 55)
assert(dynamite.missile_sprite.frames == 4 and dynamite.definition.missile.fuse == 5000)
assert(tele.missile.explosion.power == 0 and tele.missile.explosion.push_pct == 0)
assert(tele.missile.explode_on_space and tele.missile.trail.sprite == "sprites/tele_arrow/trail.png")
local worms, probes, warps, available = {}, {}, {}, nil
wa = {worms={all=function() return worms end}}
local function worm(active,hp)
  return {turn=active,hp=hp,
    fits=function(_,x,y)
      probes[#probes+1]={x,y}
      return available and available(x,y) or false
    end,
    warp=function(_,pos) warps[#warps+1]=pos;return true end}
end
worms={worm(false,100),worm(true,100)}
available=function(x,y) return x==20.5 and y==30.25 end
tele.on_explode({x=20.5,y=30.25})
assert(#probes==1 and #warps==1 and warps[1].x==20.5 and warps[1].y==30.25)
probes,warps={},{}
available=function(x,y) return x==18 and y==27 end
tele.on_explode({x=20,y=30})
assert(#warps==1 and warps[1].x==18 and warps[1].y==27)
assert(probes[1][1]==20 and probes[2][1]==16 and probes[2][2]==26)
assert(probes[12][1]==26 and probes[13][1]==16 and probes[13][2]==27)
probes,warps,available={},{},nil
tele.on_explode({x=20,y=30})
assert(#probes==122 and #warps==0, "completely blocked destination must terminate")
probes,warps={},{}
worms={worm(false,100),worm(true,0)}
tele.on_explode({x=20,y=30})
assert(#probes==0 and #warps==0)
worms={}
tele.on_explode({x=20,y=30})
assert(#probes==0 and #warps==0)
print("Specialists weapon declarations and bounded Tele Arrow placement passed")

local hooks, actors, draws = {}, {}, {}
wa = {
  on = {worm_message=function(f) hooks.frame=f end,draw=function(f) hooks.draw=f end},
  msg={FRAME_FINISH=2},math={sin=math.sin,cos=math.cos},depth={FRONT=9},
  world={water=function()return 1000 end,gravity=function()return 0.12 end},
  draw={quad=function(q)draws[#draws+1]=q end},
  actors={spawn=function(s)
    local a={on=s.on};function a:despawn()self.dead=true end
    actors[#actors+1]=a;return a
  end},
}
dynamite.setup()
local owner={turn=true,hp=100,aiming=true,weapon="px.thrown_dynamite",aim=0.5,facing=1,x=100,y=100}
for _=1,3 do hooks.frame(owner) end
hooks.draw()
assert(#actors==1 and #draws==3 and draws[1].visibility==owner)
assert(draws[1].sprite=="sprites/thrown_dynamite/spark.png")
owner.weapon="stock.grenade";hooks.frame(owner)
for _=1,55 do actors[1].on(actors[1]) end
draws={};hooks.draw()
assert(actors[1].dead and #draws==0,"held sparks expire after selection changes")
-- A rejected updater must not leave frozen drawing data after the error.
dynamite.setup();owner.weapon="px.thrown_dynamite"
wa.actors.spawn=function()error("pool full")end
assert(not pcall(hooks.frame,owner))
draws={};hooks.draw();assert(#draws==0)
print("Thrown Dynamite sparks use one updater, inherit visibility and expire")
