-- Specialists' Gravity Gun against PX's numbers (gravity_gun_s.txt).
local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path
package.preload["wf-lib/holds"]=function()return {PX_POSTURE={},PX_HANDS={"hand1"}}end

local hooks={message={},turn_end={},draw={}}
local frame,keys,sounds,ammo,quads,traced,blocked=0,{},{},{},{},nil,false
local random_calls=0
local hold_sheet=0
local worm={id=1,kind="worm",x=100,y=100,vx=0,vy=0,hp=100,aim=0.5,facing=1,aiming=true,turn=true,
  weapon="px.gravity_gun",state="standing",alliance=0}
function worm:ammo(id,n)ammo[#ammo+1]={id,n}end
local mine={kind="mine",uid=7,x=0,y=0,vx=0,vy=0}
local mines={mine}
wa={msg={FRAME_FINISH=2},depth={EFFECTS=0xC0000,WORMS=0xD0000},
  math={sin=math.sin,cos=math.cos},
  world={frame=function()return frame end,keys=function()return keys end,
    trace=function(q)return traced and traced(q) end,
    collides=function()return blocked end},
  worms={all=function()return {worm}end},
  mines={all=function()return mines end},crates={all=function()return {}end},
  oil={all=function()return {}end},graves={all=function()return {}end},
  random=function(lo,hi)random_calls=random_calls+1;return math.floor((lo+hi)/2)end,
  sound={play=function(_,s)sounds[#sounds+1]=s end},
  weapons={hold_sheet=function(id,n)assert(id=="px.gravity_gun");hold_sheet=n end},
  on={worm_message=function(f)hooks.message[#hooks.message+1]=f end,
    turn_end=function(f)hooks.turn_end[#hooks.turn_end+1]=f end,
    draw=function(f)hooks.draw[#hooks.draw+1]=f end},
  draw={quad=function(q)quads[#quads+1]=q end,random=function()return 0.5 end},
  hud={message_top=function(t)tips[#tips+1]=t end}}
local function check(ok,what)assert(ok,what);print("  ok   "..what)end
local function each(list,...)for _,f in ipairs(list) do f(...) end end
local function step(k)keys=k or {};frame=frame+1;each(hooks.message,worm,2)end
local function near(a,b)return math.abs(a-b)<1e-9 end
local function last(name)return sounds[#sounds]=="sounds/gravity_gun/"..name..".wav" end

tips={}
dofile(root.."../tests/tooltip_mock.lua")(root)
local gun=require("weapons/gravity_gun")
gun.setup()
check(gun.definition.wep=="weps/gravity_gun.wep","Gravity Gun: PX's scheme record")
-- Aim flat right: the aim line runs along +x.
local function at(x)traced=function()return {hit=true,x=x-9,y=100,obj=mine} end;mine.x,mine.y=x,100 end

for _=1,15 do step() end -- the gun's 15-frame readiness
check(tips[#tips]=="Gravity Gun: ready\nSpace: grab\nShift/Ctrl + Space: push","the tooltip: ready, then its keys")
gun.definition.on_fire({worm=worm})
check(ammo[1][1]=="px.gravity_gun" and ammo[1][2]==1 and last("gg_claws"),"fire arms it for free, with the claws")
at(400);step({space=true})
check(near(mine.vx,-5) and near(mine.vy,0),"far (300 px): pulled at 5")
check(tips[#tips]:find("^Gravity Gun: armed\n"),"the tooltip: armed while it pulls")
check(hold_sheet==1,"the claws open while the aim has something to take")
at(200);step({space=true})
check(near(mine.vx,-12.5) and last("gg_pickup"),"within 125 px: pulled at 12.5, the pickup sound once")
local n=#sounds;at(190);step({space=true})
check(#sounds==n,"no second pickup sound while it keeps coming")
traced=function()return {hit=true,x=140,y=100,obj=mine} end
step({space=true});step({})
check(near(mine.x,140) and near(mine.y,100) and mine.vx==0 and mine.vy==0,
  "within 40 px it is caught and held 40 px in front of the worm along the aim")
check(tips[#tips]:find("^Gravity Gun: holding\n"),"the tooltip: holding")
worm.aim=0.6;step({})
local ex,ey=100+40*math.sin(0.4*math.pi),100-40*math.cos(0.4*math.pi)
check(math.abs(mine.x-ex)<1e-9 and math.abs(mine.y-ey)<1e-9,"the aim moves: the held mine follows")
worm.aim=0;local hx,hy=mine.x,mine.y;step({})
check(mine.x==hx and mine.y==hy,"too far a swing in one frame: PX leaves it where it was")
worm.aim=0.5;step({})
-- Space again lets go, then 15 frames of rest.
step({space=true})
local x=mine.x;step({});step({})
check(mine.x==x,"Space again drops it")
for _=1,15 do step() end
-- Shift and Space throw what the aim meets.
traced=function()return {hit=true,x=130,y=100,obj=mine} end
local before=#ammo;step({space=true,shift=true})
check(near(mine.vx,8.5) and near(mine.vy,0) and ammo[before+1][2]==-1 and last("gg_throw"),
  "Shift+Space throws it at 8.5 and spends the shot")
for _=1,15 do step() end
traced=function()return {hit=true,x=150,y=100} end
worm.vx,worm.vy=0,0;step({space=true,ctrl=true})
check(near(worm.vx,-2.5) and near(worm.vy,0),"thrown at land, the worm recoils (5 x 0.1 x 5 for a few worms)")
-- Held but blocked: it gives up after 75 frames.
for _=1,15 do step() end
gun.definition.on_fire({worm=worm});traced=function()return {hit=true,x=140,y=100,obj=mine} end
step({space=true});step({})
blocked=true
for _=1,80 do step({}) end
local x2=mine.x;blocked=false;step({});step({})
check(mine.x==x2,"blocked for 75 frames, it lets go")
-- A turn's end lets go too.
for _=1,15 do step() end
gun.definition.on_fire({worm=worm});step({space=true});step({})
each(hooks.turn_end);mine.x=500;step({})
check(mine.x==500,"a turn's end lets go")
traced=nil;step({})
check(hold_sheet==0,"nothing on the aim: the claws close")
-- Drawing never touches WA's generator.
local calls=random_calls
for _=1,5 do quads={};each(hooks.draw) end
check(random_calls==calls,"drawing leaves WA's random numbers alone")
print("Specialists Gravity Gun: ALL PASS")
