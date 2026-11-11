-- Megashark: a burst of twelve homing bullets, four to a target, each exploding on impact.

local seq = require("lib/fire_seq")
local sb = require("lib/px_sprite_builder")
local trail = require("wf-lib/effects/trail")
local targetting = require("lib/targetting_missiles")
local hold_art = require("lib/px_hold_art")

local M = {}

local function placed(ctx)
  local informed = false
  if type(ctx.weapons) == "table" then
    informed = true
    if ctx.weapons[ctx.id] ~= nil then return true end
  end
  if type(ctx.placed) == "table" then
    informed = true
    for _, weapon in ipairs(ctx.placed) do
      if weapon == ctx.id or (type(weapon) == "table" and weapon.id == ctx.id) then return true end
    end
  end
  return not informed
end

function M.install(ctx)
  if not placed(ctx) then
    wa.log("Megashark: in no panel slot; nothing registered")
    return
  end

  local ART = "sprites/megashark/"
  local SND = "sounds/megashark/"

  trail.install()
  targetting.install()
  local target_group = targetting.group()

  local SHOTS = 12 -- MS_BulletAmount 11, `<= 11`
  local SHOT_DELAY = 4 -- WA's fire interval for this record
  local SPEED = 15.5 -- missileSpeed
  local TURN = 0.53 -- homingStrength
  local ARM_DIST = 90 -- activation distance
  local COOLDOWN = 2 -- homingCooldown
  local SENSOR2 = 199900 -- sensorRadiusSqr
  local PER_TARGET = 4 -- bulletsPerTarget
  local LOW_AIM = 0.164 -- low-angle extra offset

  local TRAIL = { max = 26, every = 1, core_w = 5.0, glow_w = 10.0,
    r = 90, g = 255, b = 120 }

  local function current_worm()
    for _, w in ipairs(wa.worms.all()) do
      if w.turn then return w end
    end
  end

  wa.on.missile_frame(function(m)
    if m.weapon ~= "px.megashark" then return end
    local entry = targetting.get(m.id)
    if not entry then
      local owner = current_worm()
      entry = targetting.add(m, SPEED, TURN, nil, owner)
      if not entry then return end
      entry.sensor2 = SENSOR2
      entry.cooldown = COOLDOWN
      entry.no_target_cd = 7
      entry.arm_dist = ARM_DIST
      entry.armed = false
      entry.max_target = PER_TARGET
      entry.on_target = target_group
      if owner and not trail.has(m.id) then trail.add(m.id, owner, TRAIL) end
    end
  end)

  sb.flight(ctx, {
    weapon = "px.megashark",
    sheet = ART .. "bullet",
    anim = "none",
    frame_fn = function() return 0 end,
    z = wa.depth.OBJECTS - 1,
    mirror = false,
  })

  local hold = {
    weapon = "px.megashark",
    sheet = ART .. "hold",
    size = 90,
    keep_while_firing = false,
    put_away = true,
    weap_rotation = 1.0,
    weap_radial_rotation = 1.0,
    weap_radius = 0.0,
  }

  local spec = {
    wep = "weps/megashark_wep.wep",
    panel_icon = ART .. "icon.png",
    sprites = { ART .. "bullet", ART .. "hold", trail.BEAM, trail.GLOW },
    params = { gpu_prefix = "sprites/" },
    worm_sprites = sb.PX_POSTURE,
    hold = hold,
    sounds = { SND .. "shot.wav" },

    on_fire = function(ev)
      local w = ev.worm
      local ox = math.abs(ev.x - w.x)
      local oy = ev.y - w.y
      local speed = math.sqrt(ev.vx * ev.vx + ev.vy * ev.vy)
      if speed < 1 then speed = SPEED end

      local function dir(ww)
        local ang = (1 - ww.aim) * math.pi
        if ww.facing < 0 then ang = 2 * math.pi - ang end
        return wa.math.sin(ang), -wa.math.cos(ang)
      end

      seq.fire_seq_mis({
        weapon = "px.megashark",
        cancel_weapon = "px.megashark",
        standoff = 12,
        owner = w,
        count = SHOTS,
        delay = SHOT_DELAY,
        x = function(i, ww)
          local low = ww.aim < LOW_AIM and 2.0 or 0
          return ww.x + ww.facing * (ox + 1.3 + low)
        end,
        y = function(i, ww)
          return ww.y + oy - 3.0 - (ww.aim < LOW_AIM and 2.9 or 0)
        end,
        vx = function(i, ww)
          local dx = dir(ww)
          return dx * speed
        end,
        vy = function(i, ww)
          local _, dy = dir(ww)
          return dy * speed
        end,
        spread = { y = 0.7 },
        on_shot = function(i, ww)
          wa.sound.play(ww, SND .. "shot.wav")
        end,
      })
    end,

    on_explode = function(ev)
      local id = ev.missile
      if not id then return end
      targetting.remove(id)
      trail.drop(id)
    end,
  }
  spec.handling = { ends_turn = true }
  spec.fires = { subtype = 4 } -- PX's record has no pose; 4 is the minigun's
  hold_art.add(hold)
  wa.weapons.replace(spec)
end

return M
