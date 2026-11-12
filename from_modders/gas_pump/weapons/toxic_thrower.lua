local holds = require("wf-lib/holds")
local sb = require("wf-lib/seq-spb")
local fx = require("wf-lib/effects/px_effects")
local trail = require("wf-lib/effects/trail")
local seq = require("wf-lib/fire_seq")
local hold_art = require("wf-lib/px_hold_art")

-- Toxic gas pump: the original Toxig gas mortar (real WA missiles, normal
-- hold, sprite builder flight) fired as a burst by fire_seq instead of a Minigun.
local COUNT    = 40     -- shells per trigger pull
local DELAY    = 1      -- frames between shells
local SPREAD   = 4    -- +- velocity jitter per axis, per shell
local SPEED    = 12     -- shell launch speed (px/frame); no charge, as a gun
local STANDOFF = 24     -- px along each shell's velocity, clear of the owner
local HOLD_CELL = 45.0  -- px per cell of hold.png as px_hold_art draws it (default 90 drew it 2x)

-- Unit aim vector from the worm's LIVE aim, read on every shot (as the FAMAS
-- does), so the player can keep adjusting aim during the burst.
local function dir(w)
  local ang = (1 - w.aim) * math.pi
  if w.facing < 0 then ang = 2 * math.pi - ang end
  return wa.math.sin(ang), -wa.math.cos(ang)
end

return {
  defaults = {
    ammo = { round_start = 68 },
    crate = { chance_pct = 15, type = "weapon" },
    after_use = "retreat",
  },

  install = function(ctx)
    fx.install{ trail = false }

    -- One table for both, as the Megashark does: the engine reads it as the hold
    -- (aim and put-away frames); keep_while_firing = false hands the firing
    -- frames (0x6A/0x6B) to px_hold_art, which draws it with the same art.
    local hold = {
      weapon = ctx.id,
      sheet = "sprites/toxic_thrower/hold.png",
      size = HOLD_CELL,
      keep_while_firing = false,
      put_away = true,
      hand = holds.PX_HANDS[2],
      hand_type = 2,
      hand_radius = 0,
      hand_rotation = 1,
      hand_radial_rotation = 1,
      weap_radius = -4,
      weap_rotation = 0.5278,
      weap_radial_rotation = 1,
      hand_scale = 0.9,
      thrown = false,   -- a thrown hold swaps in the throw pose, which has no gun
    }
    wa.weapons.replace{
      name = "Gas Pump",
      copy_from = "stock.mortar",
      panel_icon = "sprites/toxic_thrower/icon.png",
      -- px_hold_art draws through the GPU atlas; without gpu_prefix the quad
      -- has no sprite to draw and the weapon vanishes in the firing frames.
      params = { gpu_prefix = "sprites/" },
      sprites = { "sprites/toxic_thrower/hold.png", "sprites/toxic_thrower/missile.png", trail.BEAM, trail.GLOW },
      missile = {
        explosion = {
          power = 0,
          push_pct = 1,
        },
        gravity_pct = 0,
        wind_pct = 50,
        fuse = 600,
        countdown = 0,
        explode_on_space = false,
        sprite = 0,
        speed_pct = 101,
        alarm_worms = true,
        ends_on_contact = { water = true, worms_normal = true, worms_acting = true, worms_roping = true, worms_jumping = true },
        trail = {
          sprite = 0,
          power = 0,
          speed = 0,
        },
        action = "bounce",
        bounce = {
          bounciness = 15,
          hits = { water = true, land = true, worms_frozen = true },
        },
        burst = "nothing",
      },
      worm_sprites = holds.PX_POSTURE,
      hold = hold,
      -- FAMAS's repeat-fire subtype (the worm keeps aiming through the burst).
      fires = { subtype = 4 },

      -- First shell here, the rest from fire_seq's timer. Position and
      -- velocity are functions of (shot, worm): live aim on every shell.
      on_fire = function(ev)
        seq.fire_seq_mis{
          weapon = ctx.id, owner = ev.worm,
          cancel_weapon = ctx.id,
          count = COUNT, delay = DELAY,
          spread = { x = SPREAD, y = SPREAD },
          standoff = STANDOFF,
          x = function(i, w) return w.x end,
          y = function(i, w) return w.y - 3 end,
          vx = function(i, w) local dx = dir(w) return dx * SPEED end,
          vy = function(i, w) local _, dy = dir(w) return dy * SPEED end,
        }
      end,

      -- Poison every worm within 22 px, then the gas burst.
      on_explode = { on = function(ev)
        for _, w in ipairs(wa.worms.all()) do
          if w.hp > 0 and math.abs(w.x - ev.x) < 22 and math.abs(w.y - ev.y) < 22 then
            w:poison(2)
          end
        end
        fx.burst{
          x = ev.x, y = ev.y,
          radius = 10,
          r = 138, g = 215, b = 146,
          thickness = 6,
          noise = 1.1,
          duration = 15,
          fade = 0.55,
          grow = 2,
          live = 20,
          ellipse = { 1, 1 },
          smoke = false,
          rebuffer = false,
        }
      end },
    }

    hold_art.add(hold)

    -- px_hold_art draws only when worm.weapon == ctx.id and state_id is 0x6A or
    -- 0x6B. This shows which of the two fails (look for the lines in wkLua.log).


    sb.flight(ctx, {
      weapon = ctx.id,
      sheet = "sprites/toxic_thrower/missile.png",
      anim = "rotation",
    })
  end,
}