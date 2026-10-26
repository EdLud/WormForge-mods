-- Minigun timing drives a separate cloud/stone launch record, as PX FireFinal did.
local ART = "sprites/precipitator/"
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
    wa.weapons.replace{
      copy_from = "stock.minigun", name = "Precipitator", panel_icon = ART .. "icon.png",
      handling = {remember_selection = false},
      -- Keep the Minigun subtype: it selects its native held/firing poses.
      gun = {bullets = 25, explosion = {bias = 0}},
      projectile = payload,
      on_fire = function(ev)
        local worm = ev.worm
        -- PX deliberately uses a triangular horizontal component, not trig.
        local aim = worm.aim
        wa.weapons.launch{weapon = ctx.id, owner = worm, x = ev.x, y = ev.y,
          vx = worm.facing * (0.5 - math.abs(0.5 - aim)) * 20,
          vy = (0.5 - aim) * 20}
      end,
    }
  end,
}
