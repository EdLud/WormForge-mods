-- Specialists' Personal Invisibility against PX's rules (personal_invis_script,
-- wosc_lib PersonalInvisibility).
local root=HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "").."../../px/")
package.path=root.."?.lua;"..package.path

local hooks={}
local frame,sounds,messages=0,{},{}
local function new_worm(id,team)
  return {id=id,team=team,alliance=team,turn=false,weapon=nil,invisibility=false}
end
local a,b,c=new_worm(1,1),new_worm(2,1),new_worm(3,2)
local worms={a,b,c}
wa={msg={FRAME_FINISH=2,FIRE_WEAPON=0x26,TURN_STARTED=0x38,WEAPON_RELEASED=0x49},
  world={frame=function()return frame end,keys=function()return {} end},
  worms={all=function()return worms end},
  hud={message_top=function(t,o)messages[#messages+1]={t,o}end},
  sound={play=function(w,s)sounds[#sounds+1]={w,s}end},
  on={worm_message=function(f,o)hooks[#hooks+1]={f=f,msgs=o.msgs}end,turn_end=function()end}}
local function send(worm,msg)
  for _,h in ipairs(hooks) do
    for _,m in ipairs(h.msgs) do if m==msg then h.f(worm,msg) end end
  end
end
local function check(ok,what)assert(ok,what);print("  ok   "..what)end
-- A team's turn starts: WA tells every worm, in one frame.
local function team_turn(active)
  frame=frame+1
  for _,w in ipairs(worms) do w.turn=(w==active) end
  for _,w in ipairs(worms) do send(w,wa.msg.TURN_STARTED) end
end
local function fire(worm,id)
  worm.weapon=id;send(worm,wa.msg.FIRE_WEAPON)
end

local pi=require("weapons/personal_invisibility")
pi.setup()
require("lib/turn_controls").setup()
check(pi.definition.utility.effect=="scripted" and pi.definition.handling.ends_turn==false,
  "a scripted utility on its own record, not WA's team Invisibility")

team_turn(a)
fire(a,"px.personal_invisibility")
check(a.invisibility and not b.invisibility and not c.invisibility,"only the worm that uses it")
check(sounds[#sounds][2]=="sounds/personal_invisibility/ding.wav","with PX's ding")
check(messages[1][1]=="Invisible for 3 turns" and messages[1][2].to=="coalition","PX's message, to the worm's side")
-- What ends it is each weapon's ends_invisibility, which the engine asks
-- for the firing worm as for its team; PX's list keeps these, whose records
-- would end it.
for _, path in ipairs({"weapons/trampoline", "weapons/tele_arrow", "weapons/weapon_crate"}) do
  local f=assert(io.open(root..path..".lua","rb"));local source=f:read("a");f:close()
  check(source:find("weapon.defaults = { ends_invisibility = false }",1,true),path.." keeps it, as PX's list")
end
a.invisibility = false

-- Four team turns while invisible, counted for every team's turn.
fire(a,"px.personal_invisibility")
local n=#sounds
team_turn(c);team_turn(a);team_turn(c)
check(a.invisibility and #sounds==n,"three team turns: still invisible")
team_turn(a)
check(not a.invisibility and sounds[#sounds][1]==a,"the fourth: visible again, with the ding")
-- The count is per worm and only restarts when it runs out.
team_turn(c)
fire(c,"px.personal_invisibility")
team_turn(a);team_turn(c)
fire(c,"px.personal_invisibility")
check(not c.invisibility,"firing it again turns it off")
fire(c,"px.personal_invisibility")
team_turn(a);team_turn(c)
check(not c.invisibility,"turned off early, it keeps the turns it had left (PX's invisibilitycount)")
print("Specialists Personal Invisibility: ALL PASS")
