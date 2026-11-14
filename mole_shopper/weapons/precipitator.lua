-- Precipitator: fire 25 clouds that release falling explosive stones.

local ART = "sprites/precipitator/"
-- The ripple a stone sends through the picture where it lands.
local RIPPLE = {amplitude = 4, wavelength = 24, speed = 180, duration_ms = 450, falloff = 36}
local payload = {
  copy_from = "stock.grenade", sprite = ART .. "body.png",
  cluster = {sprite = ART .. "fragment.png"}, params = {sprite_columns = 1},

    fires = {
      launch_power_pct = 99,
      subtype = 3,
    },
    missile = {
      alarm_worms = false,
      animation = 6,
      burst = "clusters",
      countdown = 0,
      flight_sound = 36,
      fuse = 5000,
      gravity_pct = -1,
      impact_particles = false,
      random_motion = 10,
      speed_pct = 99,
      bounce = {
        bounciness = 50,
        contact_sides = 0,
        max_bounces = 100,
        sound = 0,
        terrain_keep_speed_pct = 50,
        hits = {
          crates = true,
          donor_cards = true,
          land = true,
          objects = true,
          water = true,
        },
      },
      ends_on_contact = {
        water = true,
      },
      explosion = {
        bias = 0,
        power = 0,
        push_pct = 0,
      },
      explosion_sound = {
        before = 1,
        sound = 36,
      },
      trail = {
        power = 4,
        speed = 50,
        sprite = ART .. "snow.png",
      },
    },
    clusters = {
      angle = -1,
      count = 1,
      power_variation_pct = 100,
      bit = {
        action = "bounce",
        animation = 1,
        flight_sound = 58,
        fuse = 10000,
        gravity_pct = 145,
        impact_particles = true,
        random_motion = 4,
        speed_pct = 100,
        sprite_count = 1,
        bounce = {
          bounciness = 30,
          max_bounces = 100,
          sound = 106,
          terrain_keep_speed_pct = 30,
          hits = {
            water = true,
            worms_frozen = true,
          },
        },
        ends_on_contact = {
          crates = true,
          donor_cards = true,
          land = true,
          mines = true,
          objects = true,
          water = true,
          worms_acting = true,
          worms_jumping = true,
          worms_roping = true,
        },
        explosion = {
          power = 18,
          push_pct = 370,
        },
        trail = {
          bubbles_per_second = 12.5,
          power = 10,
          speed = 240,
          sprite = ART .. "stone.png",
        },
      },
    },
}

return {
  install = function(ctx)
    -- Stones are WA cluster bits, which no on_explode reaches: one that WA stops running has landed.
    local seen = {} -- missile id -> {x, y, frame, cloud}
    wa.on.missile_frame(function(m)
      if m.weapon ~= ctx.id or m.phase ~= "post" then return end
      local s = seen[m.id]
      if not s then s = {}; seen[m.id] = s end
      s.x, s.y, s.frame = m.x + m.vx, m.y + m.vy, wa.world.frame()
    end)
    if wa.on.draw and wa.view and wa.view.ripple then
      wa.on.draw(function()
        local now = wa.world.frame()
        for id, s in pairs(seen) do
          if now - s.frame >= 2 then
            seen[id] = nil
            if not s.cloud and s.x then
              wa.view.ripple{x = s.x, y = s.y, amplitude = RIPPLE.amplitude,
                wavelength = RIPPLE.wavelength, speed = RIPPLE.speed,
                duration_ms = RIPPLE.duration_ms, falloff = RIPPLE.falloff}
            end
          end
        end
      end)
    end
    wa.weapons.replace{
      copy_from = "stock.minigun", name = "Precipitator", panel_icon = ART .. "icon.png",
      handling = {remember_selection = false},
      gun = {bullets = 25, explosion = {bias = 0}},
      projectile = payload,
      on_fire = function(ev)
        local worm = ev.worm
        local aim = worm.aim
        local id = wa.weapons.launch{weapon = ctx.id, owner = worm, x = ev.x, y = ev.y,
          vx = worm.facing * (0.5 - math.abs(0.5 - aim)) * 20,
          vy = (0.5 - aim) * 20}
        if id then seen[id] = {frame = wa.world.frame(), cloud = true} end
      end,
    }
  end,
}
