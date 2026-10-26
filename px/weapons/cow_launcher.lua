-- Cow Launcher: record, art and behaviour.
local weapon = {}

-- Native record settings. Edit this weapon here; imported records are review drafts.
weapon.record = {
  fires = {
    launch_power_pct = 50,
    method = 3,
    subtype = 3,
    type = 1,
  },
}

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.mad_cow",
    name = "Cow Launcher",
    panel_icon = "sprites/launchers/cow_launcher_ico.png",
  })
end

-- The "charged" option: held fire sets the launch power, as WA's Bazooka.
-- Off keeps Project X's fixed launch at half power.
function weapon.configure(ctx, spec)
  if ctx.option("charged") then
    spec.fires.launch_power_pct = "charged"
  end
end

return weapon
