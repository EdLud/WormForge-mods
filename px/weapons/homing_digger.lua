-- Homing Digger: a thrown cluster bomb that homes on the clicked target, then digs on through the land and bursts into fire.

local weapon = {}

local ART = "sprites/homing_digger/"
local DIGGER_SPRITE = 54 -- the stock cluster bit's, which the digger flies with
local DIG_SOUND = 65574 -- the Mole Bomb's digging sound

weapon.record = {
  missile = {
    action = "homing",
    burst = "nothing",
    countdown = 0, -- no timer: the bomb goes off on contact, or after PX's default 5 seconds
    fuse = 5000,
    ends_on_contact = {
      crates = true,
      donor_cards = true,
      land = true,
      objects = true,
      water = true,
      worms = true,
      worms_frozen = true,
    },
    explosion = {
      bias = 0,
      power = 0,
      push_pct = 20,
    },
    homing = {
      animation = 2,
      arm = 500,
      kind = "lock",
      sprite = "cluster",
      time = 3000,
      trail = {
        power = 13,
        speed = 75,
        sprite = 116,
      },
    },
  },
}

-- What the digger changes in the bomb's record: it digs through land, Space
-- sets it off, and it bursts into fire after three seconds.
local DIGGER = {
  action = "dig",
  sprite = DIGGER_SPRITE,
  fuse = 3000,
  countdown = 0,
  explode_on_space = true,
  explosion = { power = 40, bias = 1 },
  trail = { sprite = 131, power = 20, speed = 100 },
  ends_on_contact = {
    crates = true,
    donor_cards = true,
    objects = true,
    worms_normal = true,
  },
  dig = {
    sound = DIG_SOUND,
    dive_sprite = DIGGER_SPRITE,
    sprite_1 = DIGGER_SPRITE,
    sprite_2 = DIGGER_SPRITE,
    sprite_3 = DIGGER_SPRITE,
  },
  burst = "fire",
  fire = {
    spread_generations = 10,
    spread_delay_ms = 30,
    burn_time_ms = 1500,
    decay_mode = "resting",
  },
}

weapon.missile_sprite = {
  sheet = "sprites/homing_fire_cluster/clustlet.png", frames = 1, spin = true, hide = true,
  first_sprite = DIGGER_SPRITE,
}

local diggers = {} -- missile id -> true: a digger, which ends it
local pending = {} -- diggers to launch once the bomb's burst is over
local shooter
local launching = false -- a burst now is a digger's, bursting as WA builds it

local function on_explode(ev)
  local id = ev.missile
  if not id then return end
  if launching or diggers[id] then
    diggers[id] = nil
    return
  end
  pending[#pending + 1] = { x = ev.x, y = ev.y, vx = ev.vx or 0, vy = ev.vy or 0 }
end

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.cluster_bomb",
    name = "Homing Digger",
    panel_icon = ART .. "homing_digger_ico.png",
    sprite = "cluster",
    on_explode = on_explode,
    sprites = { "sprites/homing_fire_cluster/clustlet.png" },
  })
end

function weapon.setup()
  diggers, pending, shooter, launching = {}, {}, nil, false

  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FIRE_WEAPON and worm.weapon == "px.homing_digger" then
      shooter = worm
      return
    end
    if msg ~= wa.msg.FRAME_FINISH or #pending == 0 then return end
    local owner = shooter or worm
    local list = pending
    pending = {}
    launching = true
    for _, p in ipairs(list) do
      local ok, id = pcall(wa.weapons.launch, {
        weapon = "px.homing_digger", owner = owner, x = p.x, y = p.y, vx = p.vx, vy = p.vy,
        missile = DIGGER,
      })
      if ok and id then diggers[id] = true end
    end
    launching = false
  end, { msgs = { wa.msg.FIRE_WEAPON, wa.msg.FRAME_FINISH } })
end

return weapon
