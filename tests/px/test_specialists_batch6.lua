-- Specialists batch 6: Bulldozer, Barrel Launcher and Trampoline, against
-- PX's numbers (PushBldzr_yellow.txt, bl_script.txt, trampolineDestr.txt).
local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path
package.preload["wf-lib/holds"]=function()return {PX_POSTURE={},PX_HANDS={"hand1","hand2","hand3"}}end
local turn_worm
local shared={current_worm=function()return turn_worm end}
package.preload["lib/shared"]=function()return shared end

local hooks={missile={},message={},turn_start={},turn_end={},draw={},explode={}}
local log={cuts={},hurts={},hits={},spawned={},drums={},sounds={},messages={},fires={},mines={},ammo={},quads={}}
local frame,collides=0,false
local worms,mines,crates,oil={}, {}, {}, {}
wa={
  msg={FRAME_FINISH=2},depth={OBJECTS=0xE0000},
  world={frame=function()return frame end,keys=function()return {digit=turn_worm and turn_worm.digit}end,
    collides=function()return collides end,cavern=function()return false end},
  land={cut=function(c)log.cuts[#log.cuts+1]=c end},
  worms={all=function()return worms end},
  mines={all=function()return mines end,spawn=function(s)
    local m={uid=500+#log.mines,gravity=1,visible=true}
    for k,v in pairs(s) do m[k]=v end
    log.mines[#log.mines+1]=m;return m end},
  crates={all=function()return crates end},
  oil={all=function()return oil end,spawn=function(s)
    local d={uid=100+#log.drums,x=s.x,y=s.y,vx=0,vy=0,snap=s.snap,visible=true,damage=0,max_damage=50}
    log.drums[#log.drums+1]=d;oil[#oil+1]=d;return d end},
  fire={spawn=function(s)log.fires[#log.fires+1]=s end},
  actors={spawn=function(spec)
    local a={id=#log.spawned+1,x=spec.x,y=spec.y,vx=spec.vx or 0,vy=spec.vy or 0,spec=spec,booms={}}
    function a:despawn()self.id=0 end
    function a:explode(e)self.booms[#self.booms+1]=e end
    log.spawned[#log.spawned+1]=a;return a end},
  sound={play=function(t,s)log.sounds[#log.sounds+1]=s end},
  hud={message_top=function(t)log.messages[#log.messages+1]=t end},
  assets={load=function()end},
  random=function(lo,hi)return lo end,
  log=function()end,
  on={missile_frame=function(f)hooks.missile[#hooks.missile+1]=f end,
    worm_message=function(f)hooks.message[#hooks.message+1]=f end,
    turn_start=function(f)hooks.turn_start[#hooks.turn_start+1]=f end,
    turn_end=function(f)hooks.turn_end[#hooks.turn_end+1]=f end,
    draw=function(f)hooks.draw[#hooks.draw+1]=f end,
    oil_explode=function(f)hooks.explode[#hooks.explode+1]=f end},
  draw={quad=function(q)log.quads[#log.quads+1]=q end},
}
local function each(list,...)for _,f in ipairs(list) do f(...) end end
local function check(ok,what)assert(ok,what);print("  ok   "..what)end
local function tramp_quad()
  for _,q in ipairs(log.quads) do if q.sprite:find("trampoline/",1,true) then return q end end
end

-- Bulldozer ------------------------------------------------------------------
local bulldozer=require("weapons/bulldozer")
bulldozer.setup()
check(bulldozer.definition.wep=="weps/bulldozer.wep","Bulldozer: PX's scheme record")
local function worm(id,x,y)
  local w={id=id,x=x,y=y,hp=100,kind="worm"}
  function w:hurt(h)log.hurts[#log.hurts+1]={id=self.id,h=h}end
  return w
end
local function object(x,y)
  local o={x=x,y=y}
  function o:hit(d,vx,vy)log.hits[#log.hits+1]={o=self,d=d,vx=vx,vy=vy}end
  return o
end
turn_worm=worm(1,100,100)
worms={turn_worm,worm(2,112,100),worm(3,200,100)}
mines={object(114,100)};crates={object(81,100)};oil={object(120,100)}
each(hooks.missile,{weapon="px.bulldozer",phase="pre",id=5,x=100,y=100})
check(#log.cuts==1 and log.cuts[1].radius==10 and log.cuts[1].x==100 and math.abs(log.cuts[1].y-91.3)<1e-9,
  "Bulldozer: the newest digs a 10-pixel hole 8.7 above itself")
local force=0.6*math.sqrt(15)
check(#log.hurts==1 and log.hurts[1].id==2 and log.hurts[1].h.amount==1 and math.abs(log.hurts[1].h.vx-force)<1e-9,
  "Bulldozer: a worm in its box gets 1 damage and PX's push; the turn's worm and far worms none")
check(#log.hits==2 and log.hits[1].o==mines[1] and log.hits[2].o==crates[1] and log.hits[2].vx<0,
  "Bulldozer: a mine and a crate touching its box are hit; a drum just outside is not")
each(hooks.missile,{weapon="px.bulldozer",phase="pre",id=3,x=100,y=100})
check(#log.cuts==1,"Bulldozer: an older one pushes but no longer digs")
each(hooks.missile,{weapon="px.bulldozer",phase="post",id=5,x=100,y=100})
check(#log.cuts==1,"Bulldozer: once a frame, before WA's")

-- Barrel Launcher -------------------------------------------------------------
worms,mines,crates,oil={}, {}, {}, {}
log.hurts,log.hits={}, {}
local arcs={}
shared.electric_grenade_explode=function(e)arcs[#arcs+1]=e end
local barrel=require("weapons/barrel_launcher")
barrel.setup()
check(barrel.definition.wep=="weps/barrel_launcher.wep" and barrel.requires[1]=="weapons/electric_grenade",
  "Barrel Launcher: PX's scheme record; it needs the Electric Grenade's arc")
local shooter=worm(7,50,50);shooter.turn=true;shooter.weapon="px.barrel_launcher"
function shooter:ammo(id,n)log.ammo[#log.ammo+1]={id,n}end
turn_worm=shooter
local function press(d)shooter.digit=d;frame=frame+1;each(hooks.message,shooter,2)end
barrel.definition.on_fire({worm=shooter,x=60,y=40,vx=5,vy=-6})
local d=log.drums[1]
check(d and d.x==60 and d.y==40 and d.snap==false and d.vx==5 and d.vy==-6 and d.visible==false,
  "Barrel Launcher: the drum is built at the shell's start with its launch, WA's draw off")
press(3);press(3);press(3)
check(#log.messages==1 and log.messages[1]=="Electric Barrel" and log.sounds[#log.sounds]:find("tazsnd"),
  "Barrel Launcher: 3 picks the electric drum once, however long it is held")
press(nil);press(5)
check(log.messages[2]=="Teleport Barrel" and log.sounds[#log.sounds]==67,"Barrel Launcher: 5 the teleport drum")
press(3);barrel.definition.on_fire({worm=shooter,x=0,y=0,vx=0,vy=0})
local electric=log.drums[2]
local replaced=false
each(hooks.explode,{drum=electric,x=10,y=20,team=0,replace=function()replaced=true end})
check(replaced and #arcs==1,"Barrel Launcher: the electric drum bursts into the arc")
each(hooks.turn_end)
log.fires={}
barrel.definition.on_fire({worm=shooter,x=0,y=0,vx=0,vy=0})
each(hooks.explode,{drum=log.drums[3],x=10,y=20,team=0,replace=function()end})
check(#log.fires==3 and log.fires[1].count==15 and log.fires[1].duration==8300 and log.fires[1].damage==17,
  "Barrel Launcher: a turn's end picks napalm again; three of PX's fires")
local boom=log.spawned[#log.spawned].spec.explode
check(boom and boom.damage==30,"Barrel Launcher: napalm's blast of 30")
press(2);barrel.definition.on_fire({worm=shooter,x=0,y=0,vx=0,vy=0})
each(hooks.explode,{drum=log.drums[4],x=10,y=20,team=0,replace=function()end})
check(#log.mines==5 and log.mines[1].damage==40 and log.mines[1].fuse==3000 and log.mines[1].arm==3000,
  "Barrel Launcher: the mines drum lays five 40-damage mines")
local map={uid=999,x=0,y=0}
local map_replaced=false
each(hooks.explode,{drum=map,x=0,y=0,team=0,replace=function()map_replaced=true end})
check(not map_replaced,"Barrel Launcher: a map drum stays WA's without the oil drums add-on")
collides=true
local built=#log.drums
barrel.definition.on_fire({worm=shooter,x=0,y=0,vx=0,vy=0})
check(#log.drums==built and log.ammo[1][1]=="px.barrel_launcher" and log.ammo[1][2]==1
  and log.messages[#log.messages]=="No space to launch!" and log.sounds[#log.sounds]==120,
  "Barrel Launcher: no room, no drum: the shot is refunded")
collides=false

-- Trampoline ------------------------------------------------------------------
local trampoline=require("weapons/trampoline")
trampoline.setup()
local thrower=worm(9,100,100);thrower.facing=1
turn_worm=thrower
trampoline.definition.on_fire({worm=thrower})
local t=log.spawned[#log.spawned]
check(t.x==103 and t.y==94 and t.vx==2 and t.vy==-3 and t.spec.persist and t.spec.body.hits.land
  and t.spec.gravity==true,
  "Trampoline: thrown from the worm's x+3, y-12, 2 across and 3 up; it lands")
local function hit_by(o)t.spec.on.contact(t,{other=o})end
local jumper={kind="worm",state="jumping",x=90,vx=0,vy=4}
hit_by(jumper)
check(jumper.vy==-8 and jumper.vx==3,"Trampoline: a falling worm is thrown up 8 and across 3, to its far side")
jumper.x=110;hit_by(jumper)
check(jumper.vy==-9 and jumper.vx==-3,"Trampoline: the next throw is 9 up")
local idle={kind="worm",state="standing",x=100,vx=0,vy=0}
hit_by(idle)
check(idle.vy==0,"Trampoline: a worm standing on it stays")
local falling={kind="worm",state="jump_falling",x=100,vx=0,vy=4};hit_by(falling)
check(falling.vy<0,"Trampoline: a worm coming down from a jump is thrown")
for _,st in ipairs({"walking","charging","ready"}) do
  local w={kind="worm",state=st,x=100,vx=0,vy=1};hit_by(w)
  check(w.vy==1,"Trampoline: a "..st.." worm stays")
end
local unknown={kind="worm",state=nil,x=100,vx=0,vy=4};hit_by(unknown)
check(unknown.vy<0,"Trampoline: so does anything PX does not leave alone")
local mine={kind="mine",x=100,vx=1,vy=2};hit_by(mine)
check(mine.vy==-8,"Trampoline: mines bounce too")
local crate={kind="crate",x=100,vx=0,vy=2};hit_by(crate)
check(crate.vy==2,"Trampoline: crates do not")
log.quads={};frame=frame+1;hit_by(mine);each(hooks.draw)
check(tramp_quad().sprite:find("jumptramp",1,true),"Trampoline: the springing art the frame it throws")
log.quads={};frame=frame+1;each(hooks.draw)
check(tramp_quad().sprite:find("/tramp.png",1,true),"Trampoline: then its resting art")
-- After a turn ends it tires: 250 frames later, without a worm on turn.
each(hooks.turn_end);turn_worm=nil
for _=1,251 do t.spec.on.frame(t) end
jumper.vx,jumper.vy=1,4;hit_by(jumper)
check(jumper.vy==0 and jumper.vx==1,"Trampoline: tired after a turn's end, it only stops what lands")
each(hooks.turn_start);turn_worm=thrower;t.spec.on.frame(t)
jumper.vy=4;hit_by(jumper)
check(jumper.vy<0,"Trampoline: awake again at the next turn")
for _=1,21 do hit_by(jumper);t.spec.on.frame(t) end
jumper.vy=4;hit_by(jumper)
check(jumper.vy==0,"Trampoline: past twenty throws in a row it gives up")
hit_by(idle);t.spec.on.frame(t);jumper.vy=4;hit_by(jumper)
check(jumper.vy<0,"Trampoline: a worm standing on it resets that")
t.spec.on.hit(t,{kind="blast",blast_damage=20,x=t.x+20,y=t.y-6})
check(t.id~=0 and #t.booms==0,"Trampoline: PX's quadratic falloff: 20 pixels off a 20 blast does 15")
t.spec.on.hit(t,{damage=20})
check(t.id~=0,"Trampoline: 35 of 40 taken")
t.spec.on.hit(t,{damage=5})
check(t.id==0 and #t.booms==1 and t.booms[1].damage==10,"Trampoline: broken at 40, with a blast of 10")

-- Mine Launcher ---------------------------------------------------------------
log.mines,log.messages,log.sounds={}, {}, {}
hooks.message={}
local launcher=require("weapons/mine_launcher")
launcher.setup()
check(launcher.definition.wep=="weps/mine_launcher.wep","Mine Launcher: PX's scheme record")
local gunner=worm(11,40,60);gunner.turn=true;gunner.weapon="px.mine_launcher";gunner.alliance=2
turn_worm=gunner
local function key(d)gunner.digit=d;frame=frame+1;each(hooks.message,gunner,2)end
launcher.definition.on_fire({worm=gunner,vx=4,vy=-5})
local m=log.mines[#log.mines]
check(m.x==40 and m.y==60 and m.vx==4 and m.vy==-5 and m.arm==400 and m.fuse==0 and m.damage==50
  and m.radius==48 and m.terrain_keep_speed_pct==96 and m.visible and not m.on_bump,
  "Mine Launcher: the instant mine by default, from the worm at the shell's launch")
key(3);key(3)
check(#log.messages==1 and log.messages[1]=="Invisible Mine, 3 SEC" and log.sounds[#log.sounds]==92,
  "Mine Launcher: 3 picks the invisible mine, once a press")
launcher.definition.on_fire({worm=gunner,vx=0,vy=0})
m=log.mines[#log.mines]
check(m.arm==2000 and m.fuse==3000 and m.visible==false,"Mine Launcher: the invisible mine is never drawn")
each(hooks.message,gunner,51)
launcher.definition.on_fire({worm=gunner,vx=0,vy=0})
check(log.mines[#log.mines].fuse==0,"Mine Launcher: selecting the weapon again picks the instant mine")
key(nil);key(2)
launcher.definition.on_fire({worm=gunner,vx=6,vy=1})
m=log.mines[#log.mines]
check(m.arm==2000 and m.fuse==1500 and type(m.on_bump)=="function" and m.terrain_keep_speed_pct==nil,
  "Mine Launcher: the sticky mine hears its bumps")
mines={m}
m.on_bump(m,{x=70,y=55,other="land"})
check(m.x==70 and m.y==55 and m.vx==0 and m.vy==0 and m.gravity==0
  and log.sounds[#log.sounds-1]==107 and log.sounds[#log.sounds]==56,
  "Mine Launcher: the first touch sticks it where it hit, weightless")
key(nil)
check(m.gravity==0,"Mine Launcher: it stays stuck while nothing moves it")
m.vx=2;key(nil)
check(m.gravity==1,"Mine Launcher: moved, it falls again")
local m2=launcher.definition.on_fire({worm=gunner,vx=0,vy=0}) or log.mines[#log.mines]
m2.on_bump(m2,{x=1,y=1});m2.on_bump(m2,{x=2,y=2})
check(m2.gravity==1,"Mine Launcher: a second touch lets it fall")
each(hooks.turn_end);launcher.definition.on_fire({worm=gunner,vx=0,vy=0})
check(log.mines[#log.mines].fuse==0,"Mine Launcher: a turn's end picks the instant mine again")

print("Specialists batch 6: Bulldozer, Barrel Launcher, Trampoline and Mine Launcher: ALL PASS")
