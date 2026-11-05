local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path
local actions, wind = {}, nil
package.loaded["lib/turn_controls"] = {register=function(id,callbacks) actions[id]=callbacks end}
wa = {
  sound={play=function() end},
  world={set_wind=function(v) wind=v end},
}
require("weapons/wind_changer").setup()
local changer=actions["px.wind_changer"]
local w={turn=true,facing=1,weapon="px.wind_changer"}
local function select(weapon) w.weapon=weapon;changer.frame(w) end

select("px.wind_changer");changer.choose(w,9);changer.fire(w)
assert(wind>0.28,"a chosen force blows toward the worm's facing")
select("px.wind_changer");changer.fire(w)
assert(wind>0.28,"the force holds while the weapon stays selected")
changer.finish()
select("px.wind_changer");changer.fire(w)
assert(wind==0,"a new turn's selection starts at force 0")
changer.choose(w,5);select("stock.bazooka");select("px.wind_changer");changer.fire(w)
assert(wind==0,"reselecting within a turn starts at force 0")
changer.choose(w,3);changer.frame({turn=false,weapon="stock.bazooka"});changer.fire(w)
assert(math.abs(wind-3*0.0317)<1e-9,"other worms' frames leave the choice alone")
print("Wind Changer force resets on every selection passed")
