-- Electric Mine: a mine that sparks, arcs to nearby mines and tazes what it hits.

local fx = require("wf-lib/effects/px_effects")
local trail = require("wf-lib/effects/trail")

local DAMAGE = 45
local PUSH = DAMAGE * 2
local CLAIM = 16 -- px from the placement point to the mine entity

local function scaled(v)
  return math.floor(v * 1.25)
end

return {
  install = function()
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
      mine = { explosion = { power = 0, push_pct = 0 } },

      on_place = { on = function(ev)
        fx.mine{ owner = ev.worm, x = ev.x, y = ev.y, radius = CLAIM }
      end },

      on_explode = { on = function(ev)
        explosion.electric{
          x = ev.x, y = ev.y, owner = ev.worm,
          damage = scaled(DAMAGE), push = scaled(PUSH),
          zap = zap, fx = fx,
          effect = { depth = wa.depth.FRONT },
        }
      end },
    })
  end,
}
