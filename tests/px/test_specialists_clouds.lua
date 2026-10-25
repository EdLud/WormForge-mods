local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path
package.preload["wf-lib/holds"]=function()return {PX_POSTURE={}}end
local platform=require("weapons/platform")
local toxic=require("weapons/toxic_grenade")
local bodies,draws,hooks={}, {}, {}
local frame,sim_random,poison_calls,poison_dose=0,0,0,0
local blocked=false
local target={id=1,hp=100,x=100,y=100,turn=true}
function target:poison(n)
  assert(n==2);poison_calls=poison_calls+1
  if poison_dose==0 then poison_dose=n;return true end
  return false
end
wa={msg={TURN_STARTED=56},depth={OBJECTS=13,TERRAIN=0x180000},world={frame=function()return frame end},
  worms={all=function()return {target}end},
  land={solid=function()return blocked end},
  random=function(lo,hi)sim_random=sim_random+1;return math.floor((lo+hi)/2)end,
  actors={spawn=function(spec)
    local a={id=#bodies+1,x=spec.x,y=spec.y,vx=0,vy=0,spec=spec,booms=0}
    function a:despawn()self.id=0 end
    function a:sound(n)assert(n==112)end
    function a:explode(e)
      assert(e.damage==10 and e.id==100);self.booms=self.booms+1
      -- Native explosions can deliver another hit before the caller returns.
      self.spec.on.hit(self,{damage=100})
    end
    bodies[#bodies+1]=a;return a
  end},
  on={draw=function(fn)hooks[#hooks+1]=fn end,
    worm_message=function(fn,opts)hooks.message=fn;hooks.msgs=opts.msgs end},
  draw={random=function()return 0.5 end,quad=function(q)draws[#draws+1]=q end}}
local function render()
  draws={};for _,fn in ipairs(hooks) do fn() end
end
platform.setup();toxic.setup()
local owner={x=100,y=83,alliance=1}
platform.definition.on_fire{worm=owner,x=999,y=999}
local a=bodies[1]
assert(a.x==100 and a.y==100 and a.spec.persist and not a.spec.gravity)
assert(a.spec.body.shape=="sprites/platform/body.png" and a.spec.mask==nil)
assert(a.spec.body.hit_by=="all" and next(a.spec.body.hits)==nil)
render();assert(#draws==1 and draws[1].sprite:find("platform_sprite",1,true))
assert(draws[1].points[1][1]==30 and draws[1].points[3][2]==110)
assert(draws[1].color==0xFF0000FF and draws[1].depth==wa.depth.TERRAIN-1)
a.x,a.y,a.vx,a.vy=10,20,3,4;a.spec.on.frame(a)
assert(a.x==100 and a.y==100 and a.vx==0 and a.vy==0)
a.spec.on.hit(a,{damage=20});render()
assert(draws[1].sprite:find("platform_broken",1,true))
a.spec.on.hit(a,{damage=20});render()
assert(a.id==0 and a.booms==1 and #draws==0,"one death blast, no persistent body visual")
-- Nominal blast damage, not already-attenuated damage, drives PX's formula.
platform.definition.on_fire{worm=owner}
local b=bodies[#bodies]
b.spec.on.hit(b,{kind="blast",blast_damage=20,damage=1,x=120,y=100})
render();assert(#draws==1 and draws[1].sprite:find("platform_sprite",1,true)) --25 HP
b.spec.on.hit(b,{kind="blast",blast_damage=20,damage=1,x=120,y=100})
render();assert(draws[1].sprite:find("platform_broken",1,true)) --10 HP
b.spec.on.hit(b,{kind="blast",blast_damage=20,damage=50,x=141,y=100})
assert(b.id~=0 and b.booms==0,"outside PX's radius does no damage")
b.spec.on.hit(b,{damage=10});assert(b.id==0 and b.booms==1)
-- A native grenade detonation creates one cloud driver, never a body per puff.
assert(toxic.definition.copy_from=="stock.grenade")
assert(toxic.definition.missile.explosion.power==0 and toxic.definition.missile.burst=="nothing")
toxic.definition.on_explode{x=100,y=100}
local cloud=bodies[3]
local function step()
  frame=frame+1;cloud.spec.on(cloud)
end
assert(cloud.spec.persist and not cloud.spec.collide and not cloud.spec.gravity)
step();render();assert(#draws==6 and #bodies==3)
local before=sim_random
for _=1,10 do render();assert(#draws==6)end
assert(sim_random==before and poison_calls==0,"drawing cannot advance gameplay or RNG")
for _=1,8 do step()end
assert(poison_calls==6 and poison_dose==2,"all puffs expose, native immunity limits accepted dose")
assert(hooks.msgs[1]==55 and hooks.msgs[2]==56)
-- Tab sends the same worm-end message; after selection, another worm is active.
for _=1,6 do hooks.message(nil,55);step()end
assert(cloud.id~=0,"Tab must not spend emitter turns")
-- One broadcast visits many worms; it must spend only one cloud turn.
for _=1,4 do
  frame=frame+1
  for _=1,5 do hooks.message(nil,55)end
  -- Same-frame real next-turn starts still count once, not once per worm.
  for _=1,5 do hooks.message(nil,56)end
end
step();assert(cloud.id~=0,"source emits until the fifth turn boundary")
frame=frame+1;target.turn=false;hooks.message(nil,55)
for _=1,282 do step()end
render();assert(cloud.id==0 and #draws==0,"remaining puffs expire after emission stops")
-- Fully buried endpoints cannot hang the match in collision redirection.
toxic.definition.on_explode{x=100,y=100,worm={id=999}};cloud=bodies[4];blocked=true
assert(cloud.spec.owner==target,"a grenade outliving its owner uses a valid current body")
for _=1,10 do step()end
assert(cloud.id~=0 and #bodies==4)
print("Platform geometry, fixed placement, damage art and one death blast passed")
print("Toxic cloud simulation, native poison exposure, draw isolation, turn dedup and expiry passed")
