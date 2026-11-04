-- Specialists' Small Worm against PX's small_worm_script.
local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path

local hooks,ends,messages,cuts={},{},{},{}
local fits=true
local worm={id=1,x=100,y=200,vx=0,vy=0,gravity=1,mass=1,shape="worm",body_visible=true,facing=-1,
  state="standing",turn=true,weapon="px.small_worm",alliance=0,hp=100}
function worm:fits()return fits end
wa={msg={FRAME_FINISH=2,FIRE_WEAPON=0x26},
  world={keys=function()return {} end},
  worms={all=function()return {worm} end},
  land={cut=function(c)cuts[#cuts+1]=c end},
  hud={message_top=function(t)messages[#messages+1]=t end},
  on={worm_message=function(f,o)hooks[#hooks+1]={f=f,msgs=o.msgs}end,
    turn_end=function(f)ends[#ends+1]=f end}}
local function send(msg)
  for _,h in ipairs(hooks) do for _,m in ipairs(h.msgs) do if m==msg then h.f(worm,msg) end end end
end
local function check(ok,what)assert(ok,what);print("  ok   "..what)end
local function near(a,b)return math.abs(a-b)<1e-9 end

dofile(root .. "../tests/tooltip_mock.lua")(root)
local sw=require("weapons/small_worm")
sw.setup()
require("lib/turn_controls").setup()
check(sw.definition.utility.effect=="scripted" and sw.definition.handling.ends_turn==false,
  "a scripted utility that leaves the turn going (PX's record)")

worm.vx=1;send(wa.msg.FIRE_WEAPON)
check(worm.shape=="worm","moving, it cannot be fired (PX's CanFire)")
worm.vx=0;send(wa.msg.FIRE_WEAPON)
check(worm.shape=="mine" and worm.y==190,"small: WA's mine shape, lifted 10 px")
check(near(worm.gravity,0.75) and near(worm.mass,1.5),"three quarters of its gravity, half again its mass")
check(messages[#messages]=="Small worm mode: ON","PX's message")
check(worm.body_visible and near(worm.body_scale.scale,0.85) and worm.body_scale.y==-4,
  "its own body at 0.85 (PX's WAP->Size), on the mine shape's bottom")
-- Fired again: itself, 9 px up, stopped, gravity and mass given back.
worm.vx,worm.vy=0,0;send(wa.msg.FIRE_WEAPON)
check(worm.shape=="worm" and worm.y==181 and near(worm.gravity,1) and near(worm.mass,1),"fired again: itself again")
check(worm.body_scale==nil and messages[#messages]=="Small worm mode: OFF" and #cuts==0,"full size, no holes where it fits")
-- The turn's end ends it once it stands still; stuck, PX's holes free it.
send(wa.msg.FIRE_WEAPON)
for _,f in ipairs(ends) do f() end
worm.state="tumbling";send(wa.msg.FRAME_FINISH)
check(worm.shape=="mine","after the turn, still small while it moves")
fits=false;worm.state="standing";send(wa.msg.FRAME_FINISH)
check(worm.shape=="worm" and #cuts==6 and cuts[1].radius==5 and cuts[1].y==worm.y-4,"standing: itself, six holes when stuck")
check(worm.body_scale==nil,"full size once it is itself")
print("Specialists Small Worm: ALL PASS")
