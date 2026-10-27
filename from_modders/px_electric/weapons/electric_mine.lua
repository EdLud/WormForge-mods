-- Electric Mine -- Project X's mine extension (PX_pending/weapon_electric_mine.c).
-- WA's mine keeps placement, arming and the entity; this silences WA's blast and
-- runs PX's custom electric explosion in its place (lib/custom_explosion.lua),
-- which does the damage, push, taze, hole and effect in PX's order, and the
-- chain arcs to mines it catches. The effects SDK's px_effects draws the spark,
-- glow, two reach bolts and trail while the mine sits.
local fx = require("wf-lib/effects/px_effects")
local trail = require("wf-lib/effects/trail")

local DAMAGE = 45      -- explosion value: PX's Damage, the radius/damage basis
local PUSH = DAMAGE * 2 -- knock power, its own stat (the game default is 2x the
                        -- damage); raise it for a weak blast that still shoves
local CLAIM = 16       -- px from the placement point to the mine entity

-- PX: *1.25, truncated (weapon_electric_mine.c:97).
local function scaled(v)
  return math.floor(v * 1.25)
end

return {
  install = function()
    -- electric_damage reads wa at load, so it must wait for install.
    local zap = require("lib/electric_damage")
    local explosion = require("lib/custom_explosion")
    fx.install{ trail = true }

    wa.weapons.replace({
      copy_from = "stock.mine",
      name = "Electric Mine",
      panel_icon = "sprites/elemine.png",
      sprites = {
        "sprites/lightning/glow.png", -- the taze hold's glow
        fx.SPARK,
        fx.BLOB,
        fx.SMOKE,
        trail.BEAM,
        trail.GLOW,
        "sprites/electric_grenade/tazed1",
        "sprites/electric_grenade/tazed2",
      },
      sounds = { "sounds/lightning/tazer_loop.wav" },
      params = { gpu_prefix = "sprites/" },
      -- PX replaces WA's blast (weapon_electric_mine.c:93-102). A power of 0
      -- leaves the mine no damage and no radius of its own; on_explode runs the
      -- custom one instead.
      mine = { explosion = { power = 0, push_pct = 0 } },

      on_place = { on = function(ev)
        -- PX's TazeMine: the mine is live the moment it is placed.
        fx.mine{ owner = ev.worm, x = ev.x, y = ev.y, radius = CLAIM }
      end },

      on_explode = { on = function(ev)
        explosion.electric{
          x = ev.x, y = ev.y, owner = ev.worm,
          damage = scaled(DAMAGE), push = scaled(PUSH),
          zap = zap, fx = fx,
          -- Ring and lens in front, as the port has always drawn them.
          effect = { depth = wa.depth.FRONT },
        }
      end },
    })
  end,
}
