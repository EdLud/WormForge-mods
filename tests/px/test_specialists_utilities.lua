local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function() return {PX_POSTURE={}} end
package.preload["wf-lib/parkour"] = function() return dofile(root .. "../sdk/parkour.lua") end
local actions, hooks, sounds, banners = {}, {}, {}, {}
package.loaded["lib/turn_controls"] = {register=function(id,callbacks) actions[id]=callbacks end}
local clock,tick=30000,0
wa = {
  msg={FRAME_FINISH=2,JUMP=36,JUMP_UP=37},
  on={worm_message=function(f)hooks[#hooks+1]=f end},
  sound={play=function(w,s) sounds[#sounds+1]=s end},
  hud={message_top=function(text,opts) assert(opts.to=="coalition");banners[#banners+1]=text end},
  world={frame=function()return tick end,turn_clock=function()return clock end,set_turn_clock=function(t)clock=t end},
}
dofile(root .. "../tests/tooltip_mock.lua")(root)
require("weapons/sacrifice").setup()
local sacrifice=actions["px.sacrifice"]
local w={id=17,hp=151,turn=true,alliance=0,x=100,y=100,vx=1.5,vy=2,facing=1,state="sliding"}
function w:reduce_health(n)
  assert(n>=0 and self.hp>n)
  self.hp=self.hp-n
  return true
end
assert(sacrifice.fire(w)=="eat" and w.hp==151 and clock==30000)
sacrifice.choose(w,5);sacrifice.fire(w)
assert(w.hp==1 and clock==45000,"affordable cost is capped, retaining 1 HP")
assert(sacrifice.fire(w)=="eat","success resets the choice")
w.hp=100;sacrifice.choose(w,5);sacrifice.fire(w)
assert(w.hp==50 and clock==50000,"exact multiples cannot spend the last 50 HP")
sacrifice.choose(w,1);sacrifice.fire(w)
assert(w.hp==50 and clock==50000,"50 HP cannot buy time")
w.hp=51;sacrifice.choose(w,1);sacrifice.fire(w)
assert(w.hp==1 and clock==55000)
sacrifice.choose(w,3);sacrifice.finish()
assert(sacrifice.fire(w)=="eat","turn/control handoff clears choice")
print("Sacrifice affordability, nonlethal costs, clock and choice lifetime passed")

local right, floor = 110, nil
wa.land={trace=function(x,y,x1,y1)
  if y1>y and floor then return {hit=true,x=x,y=floor} end
  if x1>x and right then return {hit=true,x=right,y=y} end
end}
local jumps=0
function w:jump() jumps=jumps+1;self.state="jumping" end
w.hp=100
require("weapons/parkour").setup()
local parkour=actions["px.parkour"]
local utility_hook=hooks[#hooks]
-- Register the existing global option after the weapon, as a real profile does.
dofile(root .. "../utilities/features/parkour.lua")
local global_hook=hooks[#hooks]
local function input(msg)
  tick=tick+1
  utility_hook(w,msg)
  global_hook(w,msg) -- Real dispatch invokes every hook, even after "eat".
end
parkour.fire(w);input(wa.msg.JUMP)
assert(w.vx==-4.5 and w.vy==-3.5 and w.facing==-1 and jumps==1,"one wall jump, not two")
w.vx,w.vy=0,-1;input(wa.msg.JUMP)
assert(w.vx==0 and w.vy==-1,"global option cannot bypass utility cooldown")
for _=1,15 do input(wa.msg.FRAME_FINISH) end
input(wa.msg.JUMP);assert(w.vx==-3 and w.vy==-3)
parkour.fire(w);w.vx,w.vy=0,0;input(wa.msg.JUMP)
assert(w.vx==0 and w.vy==0,"toggling cannot bypass the shared movement cooldown")
for _=1,15 do input(wa.msg.FRAME_FINISH) end
input(wa.msg.JUMP)
assert(w.vx==-3 and w.vy==-2,"global movement still works when the utility is off")
parkour.fire(w);parkour.finish();w.vx,w.vy=0,0
assert(utility_hook(w,wa.msg.JUMP)==nil and w.vx==0,"handoff disables utility")
parkour.fire(w);w.state="standing"
assert(utility_hook(w,wa.msg.JUMP)==nil,"standing jump remains native")
print("Parkour reuses the global controller and owns enabled airborne inputs once")

local objects, stamps, damage, missile_hook, launch_event, draw_hook = {}, {}, {}, nil, nil, nil
package.loaded["lib/turret"]={projectile_target=function()end}
wa.on.missile_frame=function(f)missile_hook=f end
wa.on.draw=function(f)draw_hook=f end
wa.depth={FRONT=9}
wa.worms={all=function()return {w} end}
wa.world.electrical_nearby=function()return objects end
wa.land.stamp=function(s)stamps[#stamps+1]=s end
wa.weapons={launch=function(ev)
  launch_event=ev
  return 100
end}
local girder=require("weapons/girder_launcher")
girder.setup()
local def=girder.definition
assert(def.handling.shots==4 and def.fires.launch_power_pct==45)
assert(def.missile.explosion.power==0 and def.missile.explosion.push_pct==0)
local function fire(vx,vy)
  def.on_fire{worm=w,x=100,y=100,vx=vx,vy=vy}
end
for i,v in ipairs({{0,-4,0},{4,0,8},{0,4,16},{-4,0,24},{4,-4,3},{4,4,11},{-4,4,19},{-4,-4,27}}) do
  fire(v[1],v[2]);def.on_explode{missile=100,x=200,y=200}
  assert(stamps[#stamps].frame==v[3])
end
local target={kind="worm",id=18,x=200,y=200,hurt=function(self,n)damage[#damage+1]=n end}
objects={w,target};w.kind="worm";w.x,w.y=200,200
fire(12,-4);missile_hook{id=100,uid=50,weapon="px.girder_launcher",vx=8,vy=-8}
local before=#stamps
def.on_explode{missile=100,x=200,y=200}
assert(target.vx==2 and target.vy==-2 and damage[1]==3 and #stamps==before)
-- Explode during launch, before a missile handle or first frame exists.
wa.weapons.launch=function(ev)
  def.on_explode{missile=101,x=200,y=200}
  return 101
end
fire(16,8)
assert(target.vx==4 and target.vy==2 and damage[2]==3,"point-blank launch retains shot speed and owner")
assert(#stamps==before,"overlapping enemy hit, shooter excluded, no terrain stamp")
print("Girder Launcher orientation, body impact and synchronous launch passed")
