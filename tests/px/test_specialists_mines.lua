local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path
local spec=require("weapons/mines_gun").definition
local made={}
wa={mines={spawn=function(args)made[#made+1]=args;return {}end}}
local owner={id=17}
assert(spec.copy_from=="stock.uzi" and spec.gun.bullets==6 and spec.gun.shot_interval_ms==-2)
-- Native firing supplies each shot separately; Lua must not create another burst.
for i=1,6 do
  spec.on_fire{worm=owner,x=100+i/4,y=200-i/8,vx=-0.6,vy=-0.8}
  local mine=made[i]
  assert(#made==i and mine.owner==owner)
  assert(mine.x==100+i/4 and mine.y==200-i/8)
  assert(math.abs(mine.vx+7.2)<1e-9 and math.abs(mine.vy+9.6)<1e-9)
  assert(mine.arm==3000 and mine.fuse==3000 and mine.damage==30 and mine.radius==50)
  assert(mine.triggered and mine.terrain_keep_speed_pct==60 and mine.dud_proof==nil)
end
spec.on_fire{worm=owner,x=0,y=0,vx=0,vy=-1}
assert(made[7].vx==0 and made[7].vy==-12,"vertical native vectors stay vertical")
print("Mines Gun preserves native firing context and launches exactly one triggered mine per callback")
