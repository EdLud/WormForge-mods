local root = MOLE_SHOPPER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../mole_shopper/")
package.path = root .. "?.lua;" .. package.path
local frame, clock, claim, hurt, message, death, draw = 1, 60000
local sounds, quads, pushes, hints = {}, {}, {}, {}
local a = {id=17,team=1,alliance=0,hp=100,state="standing",x=12,y=34,turn=true}
local b = {id=33,team=2,alliance=0,hp=100,state="standing",x=70,y=34,turn=false}
local c = {id=18,team=1,alliance=0,hp=100,state="standing",x=30,y=34,turn=false}
local hits = 1
wa = {
  msg={FRAME_FINISH=2,TURN_STARTED=99},depth={WORMS=20},
  world={frame=function() return frame end,turn_clock=function()return clock end},
  worms={all=function() return {a,b,c} end},
  weapons={replace=function(v) claim=v end},
  on={hurt=function(f)hurt=f end, worm_message=function(f,options)
    -- The suit's own hook; the tooltip's (frame finish only) is not under test.
    if #options.msgs==2 then message=f end
  end,death=function(f)death=f end,draw=function(f)draw=f end},
  sound={play=function(w,s)sounds[#sounds+1]={w,s} end},
  draw={quad=function(t)quads[#quads+1]=t end},
  hud={message_top=function(text,to)hints[#hints+1]={text,to} end},
  fire={repel=function(t)pushes[#pushes+1]=t;return hits end},
  sorted=function(t)local out={};for k in pairs(t)do out[#out+1]=k end;table.sort(out);return out end,
}
dofile(root .. "../tests/tooltip_mock.lua")(root)
require("weapons/antifire_suit").install()
assert(claim.utility.effect=="scripted" and not claim.handling.ends_turn)
local function hit(w,kind,phase) return hurt{worm=w,kind=kind,phase=phase or "pre",amount=10} end
assert(hit(a,"fire")==nil)
claim.on_fire{worm=a}
assert(#sounds==1 and #hints==1 and hints[1][2].to=="coalition")
draw();assert(#quads==1 and quads[1].color>>24==38,"activation starts with a faint shield")
message(a,2);quads={};draw()
assert(quads[1].color>>24==38,"repelling fire alone does not brighten the shield")
quads={};pushes={}
assert(hit(a,"fire")=="eat" and hit(b,"fire")==nil)
for _,kind in ipairs({"blast","hit","percent","nonlethal","poison"}) do assert(hit(a,kind)==nil) end
assert(hit(a,"fire","post")==nil)
claim.on_fire{worm=a};assert(#sounds==1,"repeated activation does not stack")
message(a,2)
assert(#pushes==1 and pushes[1].radius==28 and pushes[1].power==28 and pushes[1].x==a.x)
message(b,2);assert(#pushes==1,"other worms have no field")
draw();assert(#quads==1 and quads[1].visibility==a and quads[1].color>>24==120)
assert(quads[1].blend=="add")
-- A real turn for another team, even the same coalition, does not expire it.
a.turn=false;b.turn=true;message(b,99);assert(hit(a,"fire")=="eat")
-- A broadcast recipient without control cannot expire its own team's suit.
message(c,99);assert(hit(a,"fire")=="eat")
frame=200;quads={};draw();assert(#quads==1 and quads[1].color>>24==38,"active shield stays faintly visible")
assert(hit(a,"fire")=="eat");quads={};draw();assert(quads[1].color>>24==120,"a single fire hit flashes full red")
assert(sounds[#sounds][2]==55)
local n=#sounds;hit(a,"fire");assert(#sounds==n,"at most one sizzle per worm per frame")
claim.on_fire{worm=b};claim.on_fire{worm=c}
a.turn=true;b.turn=false;message(a,99)
assert(hit(a,"fire")==nil and hit(c,"fire")==nil and hit(b,"fire")=="eat")
b.state="drowning";message(b,2);b.state="standing";assert(hit(b,"fire")==nil)
claim.on_fire{worm=b};death{victim=b};assert(hit(b,"fire")==nil)
claim.on_fire{worm=a};a.hp=0;message(a,2);a.hp=100;assert(hit(a,"fire")==nil)
frame=205;claim.on_fire{worm=a};hit(a,"fire");quads={};draw()
local puff
for _,q in ipairs(quads) do if q.sprite:find("smoke.png") and q.frame==0 then puff=q end end
assert(puff and puff.visibility==a and puff.frame==0,"blocked flames emit scoped smoke")
frame=266;quads={};draw()
for _,q in ipairs(quads) do assert(not q.sprite:find("smoke.png"),"puffs expire") end
hits=0;claim.on_fire{worm=a};frame=500;message(a,2);quads={};draw()
assert(#quads==1 and quads[1].color>>24==38)
assert(hit(a,"hit")==nil);quads={};draw();assert(quads[1].color>>24==38,"ordinary hits do not flash the shield")
assert(hit(a,"fire")=="eat","fading shield is only presentation")
print("Antifire Suit: all Lua checks passed")
