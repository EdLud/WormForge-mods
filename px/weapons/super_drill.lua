-- Super Drill: a pneumatic drill that cuts a hole twice as wide.

local weapon = {}

weapon.record = {
  drill = {
    duration_ms = 2000,
  },
}

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.pneumatic_drill",
    name = "Super Drill",
    panel_icon = "sprites/super_drill/ico_superdrill.png",
  })
end

function weapon.setup()
  -- worm id -> its drill: a second, wider cut each game frame while the
  -- stock drill runs.
  local drills = {}

  wa.on.frame(function()
    for _, id in ipairs(wa.sorted(drills)) do
      local d = drills[id]
      local worm = d.worm
      if worm.drilling then
        d.started = true
        wa.land.cut({ x = worm.x, y = worm.y, shape = "drill" })
      elseif not d.started and d.waiting < 4 then
        d.waiting = d.waiting + 1
      else
        drills[id] = nil
      end
    end
  end)

  wa.on.worm_message(function(worm, msg)
    if worm.weapon == "px.super_drill" and not drills[worm.id]
        and worm:ammo("px.super_drill") ~= 0 then
      drills[worm.id] = { worm = worm, started = false, waiting = 0 }
    end
  end, { msgs = { wa.msg.FIRE_WEAPON } })
end

return weapon
