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
  msg = {FRAME_FINISH = 2},
  on = {
    turn_start=function(f) hooks.start[#hooks.start+1]=f end,
    turn_end=function(f) hooks.stop[#hooks.stop+1]=f end,
    worm_message=function(f, filter) assert(filter.msgs[1]==2); hooks.frame[#hooks.frame+1]=f end,
    hud=function() error("the cursor hint must not be a render-time HUD line") end,
  },
}
hooks.start, hooks.stop, hooks.frame = {}, {}, {}
local function simulation(f, ...)
  in_simulation=true
  f(...)
  in_simulation=false
end
local worm={id=17,weapon="cursors.cursor",turn=true,hp=100,alliance=4}
-- A simulation frame: the cursor's actor, then the turn's worm.
local function tick(n)
  for _=1,n or 1 do
    frame=frame+1
    if actor and not actor.dead then simulation(actor.on,actor) end
    for _, f in ipairs(hooks.frame) do simulation(f, worm, 2) end
  end
end
dofile(root .. "../tests/tooltip_mock.lua")(root)
local weapon=assert(loadfile(root .. "weapons/cursor.lua"))()
weapon.install({id="cursors.cursor"})
simulation(selected.on_select.on,{worm=worm,x=10,y=20})
tick()
assert(#messages==1 and messages[1]:find("Light",1,true) and messages[1]:find("\n+ next mode",1,true))
tick(20); assert(#messages==1, "the tooltip stays; it is not sent again")
for i, name in ipairs({"Magnet attract","Magnet repel","Revive","Freeze","Fire","Hurt","Light"}) do
  keys.plus_key=true; tick()
  assert(#messages==i+1 and messages[#messages]:find(name,1,true))
  tick(5); assert(#messages==i+1, "held plus must not change it again")
  keys.plus_key=false; tick()
end
assert(#fields==2 and fields[1].removed and fields[2].removed)
-- Another weapon: the tooltip goes; the Cursor again: its mode is back.
local before=#messages
worm.weapon="stock.bazooka"; tick(3); assert(#messages==before)
worm.weapon="cursors.cursor"; tick()
assert(#messages==before+1 and messages[#messages]:find("Light",1,true), "reselecting brings its mode back")
for _, f in ipairs(hooks.stop) do simulation(f) end
assert(actor.dead)
print("Cursor tooltips: coalition, every mode, held key, reselection and cleanup passed")
