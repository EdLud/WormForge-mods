-- Super Drill: record, art and behaviour.
local weapon = {}

-- Native record settings. Edit this weapon here; imported records are review drafts.
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
  -- Super Drill (PX weapon_super_drill): WA keeps drilling as it always does,
  -- and a hidden actor cuts a second hole at the worm each frame until WA's
  -- drill stops. The same as the super_drill example. It runs from worm
  -- messages, which WA sends in lockstep on every peer and in replays.
  local drills = {}

  local function follow_drill(worm, id)
    local started, waiting = false, 0
    return function(a)
      if worm.drilling then
        started = true
        wa.land.cut({ x = worm.x, y = worm.y, shape = "drill" })
        return
      end
      -- WA enters its drilling state a few frames after the shot.
      if not started and waiting < 4 then
        waiting = waiting + 1
        return
      end
      drills[id] = nil
      a:despawn()
    end
  end

  -- Here, not with the Fire Jump: a profile may place the drill alone.
  wa.on.worm_message(function(worm, msg)
    if worm.weapon == "px.super_drill" and not drills[worm.id]
        and worm:ammo("px.super_drill") ~= 0 then
      local id = worm.id
      drills[id] = wa.actors.spawn({
        sprite = false, x = worm.x, y = worm.y,
        gravity = false, collide = false, owner = worm,
        on = follow_drill(worm, id),
      })
    end
    -- Not eaten: WA's drill still runs.
  end, { msgs = { wa.msg.FIRE_WEAPON } })
end

return weapon
