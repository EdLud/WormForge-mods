-- TNT: Specialists 2.3's Soldier explosive (weapon_explosives), on WA's
-- Dynamite. The scheme's record is WA's Dynamite with a weaker blast that
-- bursts into three short-fused bits: three more small blasts around it.
local weapon = {}
local ART = "sprites/tnt/"

-- Native record settings, from the Specialists 2.3 scheme's dynamite slot.
-- Edit this weapon here; imported records are review drafts.
weapon.record = {
  fires = {
    launch_power_pct = 7,
  },
  handling = {
    remember_selection = false,
  },
  missile = {
    burst = "clusters",
    explosion = {
      power = 50,
      push_pct = 70,
    },
  },
  clusters = {
    angle = -1,
    count = 3,
    launch_power_pct = 40,
    power_variation_pct = 60,
    spread = 360,
    bit = {
      action = "bounce",
      fuse = 75,
      gravity_pct = 100,
      impact_particles = false,
      speed_pct = 100,
      sprite_count = 1,
      bounce = {
        bounciness = 1,
        contact_sides = 8,
        hits = {
          water = true,
        },
      },
      ends_on_contact = {
        water = true,
      },
      explosion = {
        power = 30,
        push_pct = 40,
      },
    },
  },
}

-- tnt_anim: WeapSprite type 5 over the record's sprite 0, upright, on every
-- TNT missile (its constructor arms it): the stick, and the three bits,
-- which have no sprite of their own and show it for their 75 ms.
weapon.missile_sprite = {
  sheet = ART .. "tnt.png", frames = 1, upright = true, hide = true,
}

function weapon.definition()
  local sdk = require("wf-lib/holds")
  local PX_POSTURE, PX_HANDS = sdk.PX_POSTURE, sdk.PX_HANDS
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.dynamite",
    name = "TNT",
    panel_icon = ART .. "ico_tnt.png",
    -- PX's builder takes the weapon out empty-handed (default_pick) and draws
    -- the TNT in the hand; WA's take-out shows its own stick.
    worm_sprites = {
      wdynlnk = PX_POSTURE.wthrow, wdynlnku = PX_POSTURE.wthrowu, wdynlnkd = PX_POSTURE.wthrowd,
    },
    sprites = { ART .. "tnt.png", ART .. "tnt_hold.png", ART .. "trail.png", ART .. "glow.png" },
    params = { gpu_prefix = ART },
    hold = { -- tnt_anim: held at a fixed angle (dont_rotate_with_angle) and
      -- placed, so never put away. Its 0.8 scale is baked into tnt_hold.png.
      thrown = true,
      sheet = ART .. "tnt_hold.png", hand_type = 1, hand_radius = 12,
      hand_radial_rotation = -0.95, weap_rotation = 0.45, weap_radius = 12,
      static = { weap = -0.1, hand = 0.4 }, -- ang_if_static, hand_ang_if_static
      hand = PX_HANDS[1],
    },
  })
end

-- explosives_script: do_sprite_trail_effects(75, PosX, PosY - 20) every frame
-- the TNT lies fusing: stock sprite 75 (vasebit1) as additive sparks, and the
-- glow every other frame. Drawing only, with a private random stream.
function weapon.setup()
  local shared = require("lib/shared")
  local TRAIL, GLOW, LIMIT = ART .. "trail.png", ART .. "glow.png", 256
  local particles, driver, seed, count = {}, nil, 1741, 0
  local function random()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
  end
  local function step(a)
    local wind = wa.world.wind()
    for i = #particles, 1, -1 do
      local p = particles[i]
      p.age = p.age + 1
      if p.age >= p.life then table.remove(particles, i)
      else
        p.x, p.y = p.x + p.vx, p.y + p.vy
        p.vx = p.vx / (1 + p.drag) + p.wind * wind
        p.vy = p.vy / (1 + p.drag)
      end
    end
    if #particles == 0 then driver = nil; a:despawn() end
  end
  local function emit(x, y, glow)
    if y >= wa.world.water() or #particles >= LIMIT then return end
    if not driver then
      -- Start the updater before adding any particles: a rejected spawn must
      -- not leave frozen quads behind.
      local owner = shared.current_worm() or wa.worms.all()[1]
      if not owner then return end
      driver = wa.actors.spawn{ sprite = false, owner = owner, x = x, y = y,
        gravity = false, collide = false, on = step }
    end
    local speed, heading = -3 - random() * 4, random() * 2 * math.pi
    particles[#particles + 1] = glow
      and { sheet = GLOW, x = x, y = y, vx = 0, vy = 0, age = 0, life = 10, drag = 1, wind = 0,
        angle = 0, alpha = 150, end_alpha = 150, size = 0.3, end_size = 0.15, pixels = 128,
        frames = 1, anim = 0 }
      or { sheet = TRAIL, x = x, y = y, age = 0, life = 40, drag = 0.5, wind = 2,
        vx = speed * wa.math.cos(heading), vy = speed * wa.math.sin(heading),
        angle = random() * 2.31, alpha = 255, end_alpha = 50, size = 1, end_size = 0.3,
        pixels = 80, frames = 32, anim = 0.05 }
  end
  wa.on.missile_frame(function(m)
    if m.weapon ~= "px.tnt" or m.phase ~= "post" then return end
    count = count + 1
    emit(m.x, m.y - 20, false)
    if count % 2 == 0 then emit(m.x, m.y - 20, true) end
  end)
  local quad = { frame = 0, blend = "add", depth = wa.depth.EFFECTS,
    points = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } } }
  wa.on.draw(function()
    for _, p in ipairs(particles) do
      local t = p.age / p.life
      local half = p.pixels * (p.size + (p.end_size - p.size) * t) / 2
      local c, s = math.cos(p.angle) * half, math.sin(p.angle) * half
      local v = math.floor(120 * (1 - t))
      local pt = quad.points
      pt[1][1], pt[1][2] = p.x - c + s, p.y - s - c
      pt[2][1], pt[2][2] = p.x + c + s, p.y + s - c
      pt[3][1], pt[3][2] = p.x + c - s, p.y + s + c
      pt[4][1], pt[4][2] = p.x - c - s, p.y - s + c
      quad.sprite, quad.frame = p.sheet, math.floor((p.age * p.anim % 1) * p.frames)
      quad.color = (math.floor(p.alpha + (p.end_alpha - p.alpha) * t) << 24) | (v << 16) | (v << 8) | v
      wa.draw.quad(quad)
    end
  end)
end

return weapon
