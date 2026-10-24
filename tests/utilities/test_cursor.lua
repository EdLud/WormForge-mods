-- Run from the engine checkout or the standalone mods repository.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../utilities/"
package.path = root .. "?.lua;" .. package.path
local messages, hooks, keys = {}, {}, {}
local selected, actor, frame, in_simulation = nil, nil, 0, false
local fields = {}
wa = {
  world = {
    keys = function() return keys end,
    frame = function() return frame end,
    pointer = function() return {x=0,y=0,down=false} end,
  },
  hud = {message_top = function(text, target)
    assert(in_simulation, "tooltips must be emitted by simulation callbacks")
    assert(#text <= 127 and target.to == "coalition" and target.alliance == 4)
    messages[#messages+1] = text
    return true
  end},
  weapons = {replace = function(spec) selected=spec end},
  cursor = {spawn = function(spec)
    actor = {x=spec.x,y=spec.y,on=spec.on}
    function actor:despawn() self.dead=true end
    return actor
  end},
  magnetism = {field = function(spec)
    function spec:remove() self.removed=true end
    fields[#fields+1]=spec
    return spec
  end},
  on = {
    turn_start=function(f) hooks.start=f end,
    turn_end=function(f) hooks.stop=f end,
    worm_message=function(f, filter) assert(filter.msgs[1]==51); hooks.select=f end,
    hud=function() error("the cursor hint must not be a render-time HUD line") end,
  },
}
local function simulation(f, ...)
  in_simulation=true
  f(...)
  in_simulation=false
end
local function tick(n)
  for _=1,n or 1 do
    frame=frame+1
    if actor and not actor.dead then simulation(actor.on,actor) end
  end
end
local weapon=assert(loadfile(root .. "weapons/cursor.lua"))()
weapon.install({id="cursors.cursor"})
local worm={id=17,weapon="cursors.cursor",turn=true,hp=100,alliance=4}
simulation(selected.on_select.on,{worm=worm,x=10,y=20})
tick()
assert(#messages==1 and messages[1]:find("Light",1,true))
tick(20); assert(#messages==1)
for i, name in ipairs({"Magnet attract","Magnet repel","Revive","Freeze","Fire","Hurt","Light"}) do
  keys.plus_key=true; tick()
  assert(#messages==i+1 and messages[#messages]:find(name,1,true))
  tick(5); assert(#messages==i+1, "held plus must not restart the message")
  keys.plus_key=false; tick()
end
assert(#fields==2 and fields[1].removed and fields[2].removed)
local before=#messages
simulation(hooks.select,worm,51)
tick()
assert(#messages==before+1, "reselecting the same weapon restores its mode hint")
local other={id=33,weapon=worm.weapon,turn=false,hp=100,alliance=1}
simulation(hooks.select,other,51)
tick(5); assert(#messages==before+1)
simulation(hooks.stop)
tick(5); assert(#messages==before+1 and actor.dead)
print("Cursor tooltips: coalition, every mode, held key, reselection and cleanup passed")
