-- Poison Grenade: a grenade that bursts into five clustlets, each bursting into a poison cloud.

local holds = require("wf-lib/holds")
local poison_cloud = require("lib/poison_cloud")
local weapon = {}

local ART = "sprites/poison_grenade/"
local PRIMING = "sounds/poison_grenade/cluster_priming.wav"
local CLUSTLET_SPRITE = 54 -- the stock cluster bit's, which the clustlets fly with
local CLUSTLETS = 5
local PUFFS = 41
local COLOR = 0xFA6E0C
local poison = 10

weapon.requires = { "lib/poison_cloud" }

weapon.record = {
  missile = {
    sprite = 0, -- WA draws no grenade; the art spec draws it
    burst = "nothing",
    bounce = {
      sound = 107,
    },
    explosion = {
      bias = 0,
      power = 0,
      push_pct = 10,
    },
    trail = {
      bubbles_per_second = 0.0,
      speed = 0,
      sprite = 0,
    },
  },
}

-- What a clustlet changes in the grenade's record: no blast, four seconds.
local CLUSTLET = {
  sprite = CLUSTLET_SPRITE,
  fuse = 4000,
  countdown = 0,
  explosion = { power = 0, push_pct = 0 },
  trail = { sprite = 132, power = 10, speed = 100 },
  burst = "nothing",
}

-- The clustlets first: the grenade's art takes any other of its missiles.
weapon.missile_sprite = {
  { sheet = ART .. "poisonc.png", frames = 8, animate = true, anim_speed = 1.0, hide = true,
    first_sprite = CLUSTLET_SPRITE },
  { sheet = ART .. "poisong.png", frames = 1, spin = true, hide = true },
}

local clustlets = {}
local bursts = {}
local shooter

local function on_explode(ev)
  local id = ev.missile
  if not id then return end
  if clustlets[id] then
    clustlets[id] = nil
    poison_cloud.release{ x = ev.x, y = ev.y + 10, worm = shooter, puffs = PUFFS, poison = poison, color = COLOR }
  else
    bursts[#bursts + 1] = { x = ev.x, y = ev.y }
  end
end

weapon.definition = require("lib/weapon").merge(weapon.record, {
  copy_from = "stock.grenade",
  name = "Poison Grenade",
  panel_icon = ART .. "ico_pois_gren.png",
  on_explode = on_explode,
  worm_sprites = holds.PX_POSTURE,
  sprites = { ART .. "poisong.png", ART .. "poisonc.png", table.unpack(poison_cloud.sprites) },
  params = { gpu_prefix = "sprites/toxic_grenade/" }, -- the cloud's puffs
  sounds = { PRIMING },
  hold = {
    thrown = true,
    -- The Fire Cluster Bomb's hold, at the chest: PX's values (hand_radius
    -- -9.8, weap_radius -10, hand_scale 1.2) holds it up at the face.
    sheet = ART .. "poisong.png", hand_type = 1, hand_radius = 16,
    weap_rotation = 0.5, weap_radius = 9,
    hand = holds.PX_HANDS[1],
  },
})

function weapon.configure(ctx)
  poison = ctx.option("poison") or 10
end

function weapon.setup()
  clustlets, bursts, shooter = {}, {}, nil

  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FIRE_WEAPON and worm.weapon == "px.poison_grenade" then
      shooter = worm
      return
    end
    if msg ~= wa.msg.FRAME_FINISH or #bursts == 0 then return end
    local owner = shooter or worm
    for _, p in ipairs(bursts) do
      for _ = 1, CLUSTLETS do
        local vx = wa.random(-131072, 131072) / 65536
        local vy = wa.random(-458752, -327680) / 65536
        local id = wa.weapons.launch({
          weapon = "px.poison_grenade", owner = owner, x = p.x, y = p.y, vx = vx, vy = vy,
          missile = CLUSTLET,
        })
        if id then clustlets[id] = true end
      end
      wa.sound.play(owner, PRIMING)
    end
    bursts = {}
  end, { msgs = { wa.msg.FIRE_WEAPON, wa.msg.FRAME_FINISH } })
end

return weapon
