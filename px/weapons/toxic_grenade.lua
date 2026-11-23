-- Toxic Grenade: a grenade that releases a lingering poison cloud.

local holds = require("wf-lib/holds")
local poison_cloud = require("lib/poison_cloud")
local weapon = {}
local ART = "sprites/toxic_grenade/"
local poison = 2

weapon.requires = { "lib/poison_cloud" }

local function detonate(event)
  poison_cloud.release{ x = event.x, y = event.y, worm = event.worm, turns = 4, poison = poison }
end

weapon.definition = {
  copy_from="stock.grenade",name="Toxic Grenade",
  panel_icon=ART.."img_toxicgren.png",sprite="grenade",
  handling={remember_selection=false},
  missile={explosion={power=0,push_pct=0},burst="nothing"},on_explode=detonate,
  worm_sprites=holds.PX_POSTURE,
  sprites={ART.."poisongren.png",ART.."smoke.png"},params={gpu_prefix=ART},
  hold={sheet=ART.."poisongren.png",frames=1,hand_radius=18,hand_rotation=1,
    hand_radial_rotation=1.05,weap_radial_rotation=0.9,weap_rotation=0.5,
    weap_radius=10,hand_type=1,hand_scale=0.8,thrown=true},
}
weapon.missile_sprite={sheet=ART.."poisongren.png",frames=1,hide=true}

function weapon.configure(ctx)
  poison = ctx.option("poison") or 2
end

return weapon
