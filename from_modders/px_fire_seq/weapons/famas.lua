-- FAMAS: three-round bursts of straight 13-damage bullets.

local seq = require("lib/fire_seq")
local sb = require("lib/px_sprite_builder")
local trail = require("wf-lib/effects/trail")
local hold_art = require("lib/px_hold_art")

local M = {}

local BURST_SHOTS = 3
local LAST_BURST_SHOTS = 2
local BURSTS = 4
local SHOT_GAP = 4
local LOW_AIM = 0.167
local SPEED = 23 -- PX's 20 px/frame at 115% (famas.wep 0x78)
local MIN_SPAWN_OFFSET = 18
local TRAIL = { max = 12, every = 1, core_w = 4.0, glow_w = 8.0,
  r = 255, g = 64, b = 32 }

local bursts = {} -- worm id -> bursts fired in this magazine (0..3)

local function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
  end
end

function M.install(ctx)
  trail.install()
  local SLOT = ctx.id or "px.famas"
  local ART = "sprites/famas/"
  local SND = "sounds/famas/"

  wa.on.missile_frame(function(m)
    if m.weapon ~= SLOT then return end
    m.gravity_scale = 0
    m.wind_scale = 0
    if not trail.has(m.id) then trail.add(m.id, current_worm(), TRAIL) end
  end)

  sb.flight(ctx, {
    weapon = SLOT,
    sheet = ART .. "bullet",
    anim = "track",
    frame_fn = function() return 0 end,
    z = wa.depth.OBJECTS - 1,
    mirror = false,
  })

  local hold = {
    weapon = SLOT,
    sheet = ART .. "hold",
    size = 90,
    keep_while_firing = false,
    put_away = true,
    weap_rotation = 1.0,
    weap_radial_rotation = 1.0,
    weap_radius = 0.0,
  }
  local firing = {
    weapon = SLOT,
    sheet = ART .. "firing",
    size = 90,
    weap_rotation = 1.0,
    weap_radial_rotation = 1.0,
    weap_radius = 0.0,
  }

  local spec = {
    wep = "weps/famas.wep",
    panel_icon = ART .. "icon.png",
    sprites = { ART .. "hold", ART .. "firing", ART .. "bullet",
      trail.BEAM, trail.GLOW },
    params = { gpu_prefix = "sprites/" },
    worm_sprites = sb.PX_POSTURE,
    hold = hold,
    sounds = { SND .. "famas-burst.wav", SND .. "famas-2.wav",
      SND .. "dryfire1.wav" },
    on_explode = function(ev)
      if ev.missile then trail.drop(ev.missile) end
    end,
    on_fire = function(ev)
      local w = ev.worm
      local id = w.id
      local fired = bursts[id] or 0
      local last = fired == BURSTS - 1
      local count = last and LAST_BURST_SHOTS or BURST_SHOTS
      
      local function dir(ww)
        local ang = (1 - ww.aim) * math.pi
        if ww.facing < 0 then ang = 2 * math.pi - ang end
        return wa.math.sin(ang), -wa.math.cos(ang)
      end

      seq.fire_seq_mis({
        weapon = SLOT,
        owner = w,
        count = count,
        delay = SHOT_GAP,
        cancel_weapon = SLOT,
        standoff = 8,
        x = function(i, ww)
          local dx, _ = dir(ww)
          local offset_dist = math.max(MIN_SPAWN_OFFSET, math.abs(ev.x - ww.x) + 3.0)
          return ww.x + (dx * offset_dist)
        end,
        y = function(i, ww)
          local _, dy = dir(ww)
          local offset_dist = math.max(MIN_SPAWN_OFFSET, math.abs(ev.y - ww.y) + 3.0)
          return ww.y + (dy * offset_dist) - 3
        end,
        vx = function(i, ww)
          local dx = dir(ww)
          return dx * SPEED
        end,
        vy = function(i, ww)
          local _, dy = dir(ww)
          return dy * SPEED
        end,
        on_shot = function(i, ww)
          if i == 1 then
            wa.sound.play(ww, SND .. (last and "famas-2.wav" or "famas-burst.wav"))
          end
        end,
        on_done = function(ww)
          if last then
            wa.sound.play(ww, SND .. "dryfire1.wav")
            bursts[id] = 0
          else
            bursts[id] = fired + 1
          end
        end,
      })
    end,
  }
  spec.handling = { ends_turn = false }
  spec.fires = { subtype = 4 }
  hold_art.add(firing)
  wa.weapons.replace(spec)
end

return M
