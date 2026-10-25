local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path
package.preload["wf-lib/holds"]=function()return {PX_POSTURE={},PX_HANDS={"hand.png"}}end
local hooks,arcs={},{}
package.loaded["lib/electrical"]={context=function()return {start_arc=function(ev)arcs[#arcs+1]=ev end}end}
package.loaded["lib/weapon_hint"]={register=function()end}
wa={msg={TURN_STARTED=56,FIRE_WEAPON=61},math={sin=math.sin,cos=math.cos},
  on={worm_message=function(f)hooks.worm=f end}}
local tazer=require("weapons/tazer")
tazer.setup()
local w={id=17,x=100,y=100,aim=0.5,facing=1,turn=true,hp=100,weapon="px.tazer"}
assert(hooks.worm(w,61)==nil)
tazer.definition.on_fire{worm=w}
assert(#arcs==1 and arcs[1].x==104 and math.abs(arcs[1].y-100)<1e-6)
assert(arcs[1].ignore[1]==w and arcs[1].burst==false and arcs[1].dx==1)
assert(hooks.worm(w,61)=="eat")
tazer.definition.on_fire{worm=w};assert(#arcs==1)
hooks.worm(w,51);assert(hooks.worm(w,61)=="eat","Tab/reselection cannot reset once-per-turn use")
hooks.worm(w,56);w.facing=-1;tazer.definition.on_fire{worm=w}
assert(#arcs==2 and arcs[2].x==96 and arcs[2].dx==-1)
print("Tazer direction, owner immunity and actual-shot turn limit passed")

local tick,bodies,cuts,hits,quads,randoms,drawing=0,{},{},{},{},0,false
wa={
  on={missile_frame=function(f)hooks.missile=f end,draw=function(f)hooks.draw=f end},
  weapons={data=function()return {missile={sprite=321}}end},
  world={frame=function()return tick end,water=function()return 1000 end},
  depth={OBJECTS=10},
  actors={spawn=function()error("visual trail must never spawn a simulation actor")end},
  random=function()error("visual trail must never use simulation RNG")end,
  draw={random=function()assert(drawing,"randomness belongs in draw");randoms=randoms+1;return 0.6 end,
    quad=function(q)quads[#quads+1]=q end},
  land={cut=function(q)cuts[#cuts+1]=q end},
  worms={all=function()return {w,{id=18,x=114,y=100,hp=100,turn=false,
    hurt=function(_,q)hits[#hits+1]=q end}}end},
  missiles={all=function()return bodies end},
}
local drilling=require("weapons/drilling_crew")
assert(drilling.definition.missile.burst=="clusters")
assert(drilling.definition.clusters.bit.trail.power==0 and drilling.definition.clusters.bit.trail.sprite==0)
drilling.setup()
local function sample(id,sprite,phase)
  hooks.missile{id=id,weapon="px.drilling_crew",sprite=sprite,x=100,y=100,phase=phase}
end
local function draw()
  quads={};drawing=true;hooks.draw();drawing=false
  return #quads
end
sample(1,321,"pre")
assert(#cuts==1 and cuts[1].x==100 and cuts[1].y==93 and cuts[1].radius==7)
assert(#hits==1 and hits[1].amount==0 and hits[1].vx>2 and hits[1].vy==0)
sample(1,321,"post");sample(2,322,"pre");sample(2,322,"post")
assert(#cuts==1 and #hits==1 and randoms==0,"children do not cut/push; simulation does not emit particles")
bodies={{id=2,uid=22,x=100,y=100}}
assert(draw()==0 and randoms==0)
tick=1;sample(2,322,"post")
assert(draw()==1 and randoms==2)
local n,rx,ry=randoms,quads[1].points[1][1],quads[1].points[1][2]
assert(draw()==1 and randoms==n and quads[1].points[1][1]==rx and quads[1].points[1][2]==ry,
  "paused/repeated draws neither emit nor age a particle")
assert(#cuts==1 and #hits==1,"drawing does not alter gameplay")
bodies={};tick=25;assert(draw()==0,"a skipped render expires visual data")
for i=1,500 do bodies[i]={id=100+i,uid=100+i,x=100,y=100};sample(100+i,322,"post")end
tick=26;draw();tick=27;for _,b in ipairs(bodies)do sample(b.id,322,"post")end
assert(draw()<=256,"the visual pool stays bounded even with many projectiles")
bodies={};tick=1;assert(draw()==0,"replay rewind clears the old visual trail")
assert(#cuts==1 and #hits==1)
print("Drilling Crew cuts/pushes; worker trail uses draw-only randomness, no actors, and bounded lifetimes")
