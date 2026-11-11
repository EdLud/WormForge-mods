-- Lantern: throw a permanent coalition light.

local holds = require("wf-lib/holds")
local lights = require("lib/lights")
local ART = "sprites/lantern/"
local REBOUND = 0.5
local P = holds.PX_POSTURE
local WORM_SPRITES = {wdynlnk = P.wthrow, wdynlnku = P.wthrowu, wdynlnkd = P.wthrowd}
for sheet, path in pairs(P) do WORM_SPRITES[sheet] = path end

return {
  defaults = {ammo = {round_start = 20}, delay = 0},
  install = function()
    local lanterns = {}
    wa.weapons.replace{
      copy_from = "stock.dynamite",
      name = "Lantern",
      panel_icon = ART .. "icon.png",
      is_weapon = true,
      handling = {remember_selection = false, ends_turn = false, shots = 1, retreat = 3000},
      worm_sprites = WORM_SPRITES,
      sprites = {ART .. "body.png"},
      params = {gpu_prefix = ART},
      hold = {
        sheet = ART .. "hold.png", frames = 1,
        hand = holds.PX_HANDS[1], hand_type = 1, hand_scale = 1.2,
        hand_radius = -10, hand_rotation = 0, hand_radial_rotation = 0,
        weap_radial_rotation = 0, weap_rotation = 0.5, weap_radius = -9,
        static = {hand = 10.4, weap = 0},
      },
      on_fire = function(ev)
        local worm = ev.worm
        local actor = wa.actors.spawn{
          owner = worm, sprite = ART .. "body.png",
          x = worm.x, y = worm.y - 10,
          vx = 2 * worm.facing + worm.vx, vy = -1.5 + 1.5 * worm.vy,
          persist = true, drown = true,
          body = {
            physics = "mine",
            hits = {land = true},
            hit_by = {blasts = true, worms = false, missiles = false, arrows = false, mines = false,
              actors = false, bullets = false, melee = false, fire = false, dragon_ball = false},
          },
          on = {bump = function(a, hit)
            if hit.ny ~= 0 and a.vy * hit.ny > 0 then a.vy = a.vy * REBOUND end
            if hit.nx ~= 0 and a.vx * hit.nx > 0 then a.vx = a.vx * REBOUND end
          end},
        }
        actor:gfx{scale = 0.48, tint = lights.colour(worm), depth = wa.depth.OBJECTS}
        lights.attach(actor, 110)
        lanterns[#lanterns + 1] = {actor = actor, id = actor.id}
      end,
    }
    wa.on.draw(function()
      local tick = wa.world.frame()
      for i = #lanterns, 1, -1 do
        local lamp = lanterns[i]
        if lamp.actor.id ~= lamp.id then
          table.remove(lanterns, i)
        else
          lamp.actor:gfx{scale = 0.48 + math.sin(tick / 10 + lamp.id) * 0.02}
        end
      end
    end)
  end,
}
