-- Specialists' Gravity Gun against PX's numbers (gravity_gun_s.txt).
local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path
package.preload["wf-lib/holds"]=function()return {PX_POSTURE={},PX_HANDS={"hand1"}}end

local ID="px.gravity_gun"
local hooks={message={},turn_end={},draw={}}
local frame,keys,sounds,ammo,quads,traced,blocked=0,{},{},{},{},nil,false
local random_calls=0
local hold_sheet=0
local worm={id=1,kind="worm",x=100,y=100,vx=0,vy=0,hp=100,aim=0.5,facing=1,aiming=true,turn=true,
  weapon=ID,state="standing",alliance=0,shots=1,shots_used=0}
function worm:ammo(id,n)ammo[#ammo+1]={id,n}end
local mine={kind="mine",id=7,x=0,y=0,vx=0,vy=0,alive=true}
local mines={mine}
wa={msg={FRAME_FINISH=2,FIRE_WEAPON=0x26},depth={EFFECTS=0xC0000,WORMS=0xD0000},
  math={sin=math.sin,cos=math.cos},
  world={frame=function()return frame end,keys=function()return keys end,
    trace=function(q)return traced and traced(q) end,
    collides=function()return blocked end},
  worms={all=function()return {worm}end},
  mines={all=function()return mines end},crates={all=function()return {}end},
  oil={all=function()return {}end},graves={all=function()return {}end},
  random=function(lo,hi)random_calls=random_calls+1;return math.floor((lo+hi)/2)end,
  sound={play=function(_,s)sounds[#sounds+1]=s end},
  weapons={hold_sheet=function(id,n)assert(id==ID);hold_sheet=n end},
  on={worm_message=function(f,o)hooks.message[#hooks.message+1]={f=f,msgs=o and o.msgs} end,
    turn_end=function(f)hooks.turn_end[#hooks.turn_end+1]=f end,
    draw=function(f)hooks.draw[#hooks.draw+1]=f end},
  draw={quad=function(q)quads[#quads+1]=q end,random=function()return 0.5 end},
  hud={message_top=function(t)tips[#tips+1]=t end}}
dofile(root .. "../tests/brush_mock.lua")(wa)
local function check(ok,what)assert(ok,what);print("  ok   "..what)end
local function each(list,...)for _,f in ipairs(list) do f(...) end end
-- A worm message to the handlers that asked for it; true when one ate it.
local function send(msg)
  local eaten=false
  for _,h in ipairs(hooks.message) do
    local wanted=not h.msgs
    for _,m in ipairs(h.msgs or {}) do if m==msg then wanted=true end end
    if wanted and h.f(worm,msg)=="eat" then eaten=true end
  end
  return eaten
end
local function step(k)keys=k or {};frame=frame+1;send(2)end
local put_away=0
local away
local gun_fire
-- A Space press as WA takes it: the fire message, then, unless eaten, a shot
-- counted against the use and the weapon put away after the last.
local function press(k)
  keys=k;frame=frame+1
  local shot=not send(0x26)
  if shot and worm.shots_used<worm.shots then
    worm.shots_used=worm.shots_used+1
    gun_fire({worm=worm})
    if worm.shots_used>=worm.shots then worm.weapon,worm.shots_used,put_away=nil,0,put_away+1 end
  end
  send(2)
  return shot
end
local function near(a,b)return math.abs(a-b)<1e-9 end
local function last(name)return sounds[#sounds]=="sounds/gravity_gun/"..name..".wav" end
local function tip()return tips[#tips] end

tips={}
dofile(root.."../tests/tooltip_mock.lua")(root)
local gun=require("weapons/gravity_gun")
gun_fire=gun.definition.on_fire
gun.setup()
local function rest()for _=1,16 do step() end end
-- The next turn: the gun selected afresh, no use open.
local function fresh()
  each(hooks.turn_end)
  worm.weapon,worm.shots,worm.shots_used=ID,1,0
  rest()
end
check(gun.definition.wep=="weps/gravity_gun.wep","Gravity Gun: PX's scheme record")
-- Aim flat right: the aim line runs along +x.
local function at(x)traced=function()return {hit=true,x=x-9,y=100,obj=mine} end;mine.x,mine.y=x,100 end

for _=1,15 do step() end -- the gun's 15-frame readiness
check(tip()=="Gravity Gun: ready\nSpace: grab\nShift + Space: throw\nCtrl + Space: cancel","the tooltip: ready, then its keys")
-- Space with nothing on the aim: a sound, nothing more.
local n=#sounds
check(not press({space=true}) and #sounds==n+1 and last("gg_dryfire") and worm.shots_used==0,
  "nothing on the aim: Space only clicks, no shot and no use")
at(400)
check(press({space=true}) and worm.shots_used==1 and worm.shots==2 and #ammo==0,
  "a target: Space is the use's first shot, with one more for the throws; the unit is WA's to take")
check(near(mine.vx,-5) and near(mine.vy,0),"far (300 px): pulled at 5")
check(tip():find("^Gravity Gun: armed\n"),"the tooltip: armed while it pulls")
check(hold_sheet==1,"the claws open while the aim has something to take")
at(200);step({space=true})
check(near(mine.vx,-12.5) and last("gg_pickup"),"within 125 px: pulled at 12.5, the pickup sound once")
n=#sounds;at(190);step({space=true})
check(#sounds==n,"no second pickup sound while it keeps coming")
traced=function()return {hit=true,x=140,y=100,obj=mine} end
step({space=true});step({})
check(near(mine.x,140) and near(mine.y,100) and mine.vx==0 and mine.vy==0,
  "within 40 px it is caught and held 40 px in front of the worm along the aim")
check(tip():find("^Gravity Gun: holding\n"),"the tooltip: holding")
worm.aim=0.6;step({})
local ex,ey=100+40*math.sin(0.4*math.pi),100-40*math.cos(0.4*math.pi)
check(math.abs(mine.x-ex)<1e-9 and math.abs(mine.y-ey)<1e-9,"the aim moves: the held mine follows")
worm.aim=0;local hx,hy=mine.x,mine.y;step({})
check(mine.x==hx and mine.y==hy,"too far a swing in one frame: PX leaves it where it was")
worm.aim=0.5;step({})
-- Space again lets go, no shot, then 15 frames of rest.
check(not press({space=true}) and worm.shots_used==1,"Space again drops it, and WA never sees the press")
local x=mine.x;step({});step({})
check(mine.x==x,"dropped, it stays")
rest()
-- Shift and Space throw what the aim meets: the use's last shot.
traced=function()return {hit=true,x=130,y=100,obj=mine} end
check(press({space=true,shift=true}) and near(mine.vx,8.5) and near(mine.vy,0) and last("gg_throw")
  and put_away==1 and #ammo==0,"Shift+Space throws it at 8.5, the last shot: WA puts the gun away")
fresh()
traced=function()return {hit=true,x=150,y=100} end
worm.vx,worm.vy=0,0
check(press({space=true,shift=true}) and worm.shots==1 and put_away==2,"a throw opens a use of its own, one shot")
check(near(worm.vx,-2.5) and near(worm.vy,0),"thrown at land, the worm recoils (5 x 0.1 x 5 for a few worms)")
fresh();traced=nil
check(not press({space=true,shift=true}) and last("gg_dryfire"),"Shift+Space at nothing: a click, no shot")
-- Held but blocked: it gives up after 75 frames.
traced=function()return {hit=true,x=140,y=100,obj=mine} end
press({space=true});step({})
blocked=true
for _=1,80 do step({}) end
local x2=mine.x;blocked=false;step({});step({})
check(mine.x==x2,"blocked for 75 frames, it lets go")
-- A turn's end lets go too.
rest()
check(not press({space=true}),"a second grab in the same use: WA never sees it")
step({})
each(hooks.turn_end);mine.x=500;step({})
check(mine.x==500,"a turn's end lets go")
traced=nil;step({})
check(hold_sheet==0,"nothing on the aim: the claws close")
-- Drawing never touches WA's generator.
local calls=random_calls
for _=1,5 do quads={};each(hooks.draw) end
check(random_calls==calls,"drawing leaves WA's random numbers alone")
-- The options: what the aim may take, worms by colour.
local function query()local q;traced=function(t)q=t end;step({});return q end
local function has(list,v)for _,x in ipairs(list) do if x==v then return true end end return false end
fresh()
local q=query()
check(#q.with==7 and not has(q.with,"worms") and #q.grab==2 and not has(q.grab,"worm") and #q.ignore==1 and q.ignore[1]==worm,
  "by default it takes every kind but worms, actors and missiles too")
check(gun.defaults.ends_invisibility==false,"using it leaves an invisible team hidden")
local ally={id=2,alliance=0,hp=100}
local enemy={id=3,alliance=1,hp=100}
wa.worms.all=function()return {worm,ally,enemy}end
local function configure(o,data)
  local all={grab_worms="off",grab_objects=true,grab_projectiles=true,grab_crates=true,grab_graves=true,grabs="infinite"}
  for k,v in pairs(o) do all[k]=v end
  gun.configure({data=data or {},option=function(k)assert(all[k]~=nil,"unknown option "..k);return all[k] end})
end
configure({grab_objects=false,grab_graves=false,grab_worms="all"})
q=query()
check(has(q.with,"worms") and has(q.with,"crates") and has(q.with,"terrain") and has(q.with,"actors")
  and not has(q.with,"mines") and not has(q.with,"oil") and not has(q.with,"graves")
  and not has(q.grab,"object") and has(q.grab,"worm") and has(q.grab,"projectile"),
  "objects and graves off: the aim passes over mines, oil drums, object actors and graves")
configure({grab_projectiles=false})
q=query()
check(not has(q.with,"missiles") and has(q.with,"actors") and not has(q.grab,"projectile"),
  "projectiles off: the aim passes over missiles and projectile actors")
configure({grab_worms="off",grab_objects=false,grab_projectiles=false})
q=query()
check(not has(q.with,"actors") and q.grab==nil,"no actor kind left: the aim asks for no actors")
configure({grab_worms="own"})
q=query()
check(#q.ignore==2 and q.ignore[2]==enemy,"own: the other colour's worms are passed over")
configure({grab_worms="off"})
q=query()
check(not has(q.with,"worms") and #q.ignore==1,"off: the aim passes over every worm")
-- Grabs per use: counted at each press that catches something.
configure({grabs="3"})
fresh();mine.alive=true
check(tip():find("\n3 grabs left\n",1,true),"grabs per use: the tooltip counts them")
at(140);press({space=true});step({})
check(tip():find("\n2 grabs left\n",1,true),"the grab that opens the use is one")
press({space=true})
check(tip():find("\n2 grabs left\n",1,true),"letting go is none")
rest();at(140);press({space=true})
check(tip():find("\n1 grab left\n",1,true),"the next grab is the second")
press({space=true});rest();at(140);press({space=true})
check(tip():find("\n0 grabs left\n",1,true),"the third")
step({})
away=put_away
check(press({space=true}) and put_away==away+1 and worm.weapon==nil,
  "letting go of the last grab ends the use: WA puts the gun away")
fresh()
at(140);press({space=true});step({});press({space=true});rest()
at(140);press({space=true});step({});press({space=true});rest()
at(140);press({space=true});step({})
traced=function()return {hit=true,x=130,y=100,obj=mine} end
away=put_away
check(press({space=true,shift=true}) and put_away==away+1,"so does throwing it")
fresh()
at(140);press({space=true});step({});press({space=true});rest()
at(140);press({space=true});step({});press({space=true});rest()
at(140);press({space=true});step({})
blocked=true;for _=1,80 do step({}) end;blocked=false
rest();at(140)
check(not press({space=true}) and last("gg_dryfire") and worm.weapon==ID,
  "let go some other way, none left: Space only clicks, the gun stays for a throw or Ctrl+Space")
fresh()
check(tip():find("\n3 grabs left\n",1,true),"the next use starts again at 3")
configure({})
fresh()
check(not tip():find("grab left",1,true) and not tip():find("grabs left",1,true),"unlimited grabs: no line")
-- Ctrl+Space ends the use without a throw.
away=put_away
check(not press({space=true,ctrl=true}) and put_away==away,"Ctrl+Space with no use open does nothing")
at(140);press({space=true});step({})
mine.vx=0
check(press({space=true,ctrl=true}) and put_away==away+1 and mine.vx==0 and last("gg_drop"),
  "Ctrl+Space: it drops what it holds, and the press is the use's last shot")
-- More shots per use: the throws, a grab opening the use on top.
configure({},{shots=2})
fresh();at(140);press({space=true})
check(worm.shots==3,"two throws a use, the grab that opened it a shot of its own")
rest();traced=function()return {hit=true,x=130,y=100,obj=mine} end
press({space=true,shift=true})
check(worm.weapon==ID and worm.shots_used==2,"after one throw the use goes on")
rest();press({space=true,shift=true})
check(worm.weapon==nil,"after the second WA puts the gun away")
configure({grab_worms="all"})
-- Worms on ropes and in vehicles: the gun takes the worm, which lets go first.
local function rider_worm(id,alliance,state,taken)
  local w={kind="worm",id=id,alliance=alliance,hp=100,x=300,y=100,vx=0,vy=0,state=state,taken=taken}
  function w:release(vx,vy)self.released={vx,vy};self.taken,self.state=false,"falling";self.vx,self.vy=vx,vy;return true end
  return w
end
local function grab_with(obj)
  fresh()
  traced=function()return {hit=true,x=291,y=100,obj=obj} end
  press({space=true})
end
local rider=rider_worm(2,0,"standing",true)
local heli={kind="actor",grab="worm",owner=rider,alive=true,x=300,y=100,vx=0,vy=0}
grab_with(heli)
check(rider.released and near(rider.released[1],-5) and heli.vx==0,
  "a vehicle: the aim takes its rider, who lets go of it, pulled at 5")
local roper=rider_worm(2,0,"roping",false)
grab_with(roper)
check(roper.released and near(roper.released[1],-5),"a worm on a rope lets go of it, pulled at 5")
local flyer=rider_worm(2,0,"jetpacking",false)
grab_with(flyer)
check(flyer.released,"so does a worm on a jet pack")
configure({grab_worms="own"})
local foe=rider_worm(3,1,"standing",true)
local tank={kind="actor",grab="worm",owner=foe,alive=true}
local asked=0
traced=function(qq)asked=asked+1;if asked==1 then return {hit=true,x=200,y=100,obj=tank} end;q=qq end
step({})
check(asked==2 and q.ignore[#q.ignore]==tank,"own: the other colour's vehicle is passed over")
configure({grab_worms="all"})
asked=0
local mine_own={kind="actor",grab="worm",owner=worm,alive=true}
traced=function(qq)asked=asked+1;if asked==1 then return {hit=true,x=110,y=100,obj=mine_own} end;q=qq end
step({})
check(asked==2 and q.ignore[#q.ignore]==mine_own,"its own worm's vehicle is passed over")
-- An actor: held where it fits, let go once it is gone.
local fit=true
local tramp={kind="actor",grab=true,alive=true,x=149,y=100,vx=0,vy=0}
function tramp:fits()return fit end
fresh()
traced=function()return {hit=true,x=140,y=100,obj=tramp} end
press({space=true});step({})
check(near(tramp.x,140) and tramp.vx==0,"an actor is caught and held as a mine is")
tramp.alive=false;tramp.x=500;step({});step({})
check(tramp.x==500,"a held actor that is gone is let go")
print("Specialists Gravity Gun: ALL PASS")
