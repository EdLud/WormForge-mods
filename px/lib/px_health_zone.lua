-- Health Zone -- Project X's zone launcher, ported to WormForge API 4.
--
-- PX's source is `PX_pending/weapon_zones/scripts/zone_launchers_script.txt`:
-- the `CHealthZone` class (:71-230), the missile's `ExplodeAt` that places the
-- zone (:377-384), and the in-match keys (:462-511). Its hold numbers are in
-- `scripts/health_zone_anim.txt` (:21-32), its record is
-- `weapons/health_zone_WEAP.wep`.
--
-- The weapon: WA's own standard missile (record `+0x30` fire type 1, `+0x38`
-- method 3, `+0x64` 2 -- track movement, a bazooka shell's flight) with PX's
-- `health_zone_bullet.png` drawn over it, which on impact leaves a zone. The
-- zone lasts `turns` turns and, once a second while it is active, acts on the
-- one object inside it:
--
--   * healing: +1 health to that worm, or a grave resurrected at 1 health
--     (`AddHealth`, :134-165);
--   * damaging: -1 health, never below 1 (`DamageHealth`, :118-132).
--
-- The other half of the zone's life -- its turns, its seven seconds of
-- inactivity after a turn ends, and the box it watches -- is PX's `CWZone` and
-- `CHealthZone` machinery, which the Security Grenade's sibling weapons share:
-- `lib/px_zone.lua`. The Blast Zone (`lib/px_blast_zone.lua`) and the Spot Hider
-- (`lib/px_spot_hider.lua`) are the same machine with other payloads.
--
-- The worm's aim art is the shared weapon-less library
-- (`lib/px_sprite_builder.lua`, `PX_POSTURE`) with PX's one held PNG over it,
-- exactly as `health_zone_anim.txt` states it (`hand_type` 3, the upper hand).
--
-- The zone's patch is the one thing here that is not PX's art: his two sprites
-- are WA's own (`mcrate0` / `fallout`) and no `wa.draw.quad` may draw a stock
-- sprite (see `ZONE_SHEET`), so `build_hold_library.py` generates a white disc
-- and PX's own tints colour it.
--
-- Not ported, and why:
--   * the flight trail and the aim particles (`do_sprite_trail_effects(108/106,
--     ...)`, :397-398; `DoAnimParticleEffects`, `health_zone_anim.txt:67`) --
--     there is no particle API (REPORT.md 6 #1), as with the Security Grenade's
--     own trail;
--   * the jet-fuel and sickness halves of `AddHealth`/`DamageHealth`
--     (:130, :161-162) -- the API has no jet-fuel or poison value;
--   * `fix_flip_rotation` (`health_zone_anim.txt:25`) -- no such hold field in
--     this engine (`crates/lua-host/src/api.rs:1615-1643`);
--   * the patch's fade (`ZoneParams->duration = 3`, :99) -- the quad is drawn at
--     a constant alpha, as PX's `alpha` (:105) is not modelled either; his own
--     colour carries the alpha this port uses (`HEAL_TINT`).
--
-- A component's file, and anything it requires, runs where `wa` does not exist
-- yet: this module is pure data at load and touches `wa` only in `install`.

-- Whether the profile placed this component on a panel slot (REPORT.md 11.13):
-- a slot-less registration takes the match down at turn start.
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

local M = {}

function M.install(ctx)
  if not placed(ctx) then
    wa.log("Health Zone: in no panel slot; nothing registered")
    return
  end

  local ART = "sprites/health_zone/"
  local sb = require("lib/px_sprite_builder")
  local zone = require("lib/px_zone")

  -- PX's numbers (`zone_launchers_script.txt`).
  local TURNS_MIN, TURNS_MAX = 2, 6 -- the 1..5 keys give 2..6 turns (:479-508)
  local FPS = 50                    -- a tick a second, `fps = 50` (:87)
  local MIN_HP = 1                  -- `minHP`: a damaging zone never kills (:89)
  local RADIUS = 20                 -- `CWZone(x, y, 40, 30, ...)`: a 40x30 box (:382)
  local HALF_HEIGHT = 15
  local ROTATION = math.pi          -- `ZoneParams->rot = 180` (:103)
  local ZONE_SIZE = 32              -- `ZoneParams->scale = 1.0` of a 32 px sprite (:104)
  local ZONE_DEPTH = wa.depth.WORMS + 1 -- PX's `ZPlane = 16` (:106): behind worms

  -- The zone's own patch. PX drew it with WA's sprites, named only as the
  -- literal ids 108 (`mcrate0`) and 106 (`fallout`) (:96-97, REPORT.md 16.4).
  -- Those ids *resolve* in Lua (`spawn::resolve_sprite_name`,
  -- `crates/lua-host/src/spawn.rs:1182`), but a `wa.draw.quad` may only draw a
  -- GPU sheet: the renderer asks `crate::sprite::gpu_frame(q.sprite)` and, for a
  -- stock id, logs "its sprite is not a GPU sheet" and draws nothing
  -- (`crates/engine/src/gpu.rs:999-1001`). So the patch is our own PNG, white,
  -- and PX's own tints colour it just as they coloured his.
  local ZONE_SHEET = ART .. "zone.png"
  local HEAL_TINT = 0x4164DC64   -- ARGB(65, 100, 220, 100), green (:111)
  local DAMAGE_TINT = 0x41D26464 -- ARGB(65, 210, 100, 100), red  (:112)

  -- PX's module state: `HealthPlus` and `HealthTurns` (:37, :17). The keys below
  -- change them for the rest of the match, as PX's do.
  local healing = true
  local turns = TURNS_MAX
  local digit_held, plus_held, minus_held

  -- The thrower, PX's `ClWT`/`ClWN` (:529-530): the flight actor's owner.
  local shooter

  -- PX's `AddHealth` (:134-165).
  local function add_health(obj)
    if obj.kind == "grave" then
      -- A grave with a bound worm comes back at 1 health (:143-146).
      if obj.worm_id ~= 0 then obj:revive(obj.worm_id, 1) end
    elseif obj.kind == "worm" then
      -- +1 health. PX caps at his 500 (:160); the engine caps at the scheme's own
      -- maximum, and at it `heal` does nothing -- which is what PX's guard means.
      obj:heal(1)
    end
  end

  -- PX's `DamageHealth` (:118-132).
  local function damage_health(obj)
    if obj.kind == "worm" and obj.hp > MIN_HP then obj:hurt(1) end
  end

  -- Whether PX's `start_be_inactive` branch would act on this activator at all:
  -- only a resting one (:209, `SpX == 0 && SpY == 0`). A grave here never moves,
  -- so it always passes.
  local function resting(obj)
    if obj.kind == "grave" then return true end
    return (obj.vx or 0) == 0 and (obj.vy or 0) == 0
  end

  -- PX's `CHealthZone`, through the shared machine: a 40x30 box, a tick a
  -- second, healing or damaging the one object inside it (:118-229).
  local ZONES = zone.register({
    name = "Health Zone",
    fps = FPS,
    radius = RADIUS,
    half_height = HALF_HEIGHT,
    kinds = { worm = true, grave = true },
    wakes = function(z, obj) return not z.start_be_inactive or resting(obj) end,
    tick = function(z, obj)
      if z.healing then add_health(obj) else damage_health(obj) end
    end,
    -- PX's zone animation is one static sheet, rotated 180 (:103), tinted and
    -- blended down (:105, :111-112). Drawn as the engine's quad rather than as
    -- the actor's sprite so the tint and the rotation are the engine's -- and
    -- because a stock sprite cannot be a quad at all (see `ZONE_SHEET`).
    draw = function(z)
      zone.mark(ZONE_SHEET, z.x, z.y, ZONE_SIZE, ROTATION,
        z.healing and HEAL_TINT or DAMAGE_TINT, "alpha", ZONE_DEPTH, 0)
    end,
  })

  -- PX's in-match keys (:462-511): 1..5 set the turns (to 2..6), `+` heals and
  -- `-` damages. PX gates each change behind two presses (`SH_pressing`, :466);
  -- here one press acts, on the key's edge, which is what PX's gate is standing
  -- in for. The digit is the one held, 0..9 or nil (`crates/lua-host/src/spawn.rs:825-829`).
  --
  -- The thrower comes from the same place PX takes it: `FireFinal` saves `ClWT` /
  -- `ClWN` (:529-530), which here is the worm the engine says fired this component.
  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FIRE_WEAPON then
      if worm.weapon == "px.health_zone" then shooter = worm end
      return
    end
    local keys = worm.turn and worm.weapon == "px.health_zone" and wa.world.keys() or nil
    local digit = keys and keys.digit
    if keys then
      if digit and digit >= 1 and digit <= 5 and digit ~= digit_held then
        turns = math.min(TURNS_MAX, math.max(TURNS_MIN, digit + 1))
      end
      if keys.plus_key and not plus_held then healing = true end
      if keys.minus_key and not minus_held then healing = false end
    end
    -- Held past the weapon's deselect, re-select and press would read as no
    -- edge: the flags track the key even while another weapon is out.
    digit_held = digit
    plus_held = keys ~= nil and keys.plus_key or false
    minus_held = keys ~= nil and keys.minus_key or false
  end, { msgs = { wa.msg.FIRE_WEAPON, wa.msg.FRAME_FINISH } })

  -- The worm whose turn it is -- PX's `GetCurrentWorm()`.
  local function current_worm()
    for _, w in ipairs(wa.worms.all()) do
      if w.turn then return w end
    end
  end

  if wa.on.hud then
    wa.on.hud(function()
      local worm = current_worm()
      if worm and worm.weapon == "px.health_zone" then
        wa.hud.line((healing and "Health Zone: HEALING" or "Health Zone: DAMAGING")
          .. " for " .. turns .. " turns  (1-5 turns, + heals, - damages)")
      end
    end)
  end

  -- **The round in flight, drawn and turned by hand.** PX's `WeapSprite` with an
  -- empty `WeapSpriteParams` (`health_zone_anim.txt:37-47`) leaves WA's sprite 0
  -- and draws PX's `health_zone_bullet.png` on the missile, turned by the
  -- record's own animation type: `+0x64` is 2, the track-movement type, a
  -- bazooka shell facing its flight (`highlander_0rang3_test/lib/missile_sprites.lua:22-25`).
  sb.flight(ctx, {
    weapon = "px.health_zone",
    sheet = ART .. "bullet.png",
    anim = "track",
    z = wa.depth.OBJECTS - 1,
    mirror = true,
    owner = shooter,
  })

  -- **The worm's aim and pick art**, PX's sprite-builder split in two: the engine
  -- draws WA's worm from the shared library's weapon-less posture
  -- (`worm_sprites`, below), then draws the held vial and its hand over it from
  -- `hold`. The numbers are PX's own (`health_zone_anim.txt:24-30`):
  -- `hand_rotation` 0.5, `hand_radius` 4, `hand_radial_rotation` 0,
  -- `hand_type` 3 (the upper hand), `weap_radius` 0 (the vial at the worm's own
  -- centre), `hand_scale` 0.8; `weap_rotation` and `weap_radial_rotation` are left
  -- at PX's defaults, 1.0. One vial PNG, turned and placed by the aim.
  local hold = {
    sheet = ART .. "hold.png",
    hand = sb.PX_HANDS[3], -- hand_type 3: the upper hand
    hand_radius = 4.0,
    hand_rotation = 0.5,
    hand_radial_rotation = 0.0,
    hand_scale = 0.8,
    weap_radius = 0.0,
    weap_rotation = 1.0,
    weap_radial_rotation = 1.0,
    frames = 1, -- one vial, turned by the engine's hold to the aim
    thrown = true, -- a thrown round leaves the hand; no put-away animation
    -- Gone on space, as PX's: no `FSprite` firing sprite, so his `sprite = 0`
    -- (`worms_anims_script.txt:263`, :419-422).
    keep_while_firing = false,
  }

  local spec = {
    -- The record is PX's own for this weapon, byte for byte: WA's standard
    -- missile with PX's icon, so the flight is WA's and only the zone is Lua's.
    wep = "weps/health_zone_wep.wep",
    panel_icon = ART .. "icon.png", -- PX's own (hz_ico.png)
    -- Stock WA art for the record itself. PX's record points its sprite at one of
    -- PX's own (id 100000+, which the engine resets); ours is never drawn --
    -- `sb.flight` hides it (`m.sprite = 0`, `lib/px_sprite_builder.lua:121`) and
    -- draws PX's own bullet instead -- but a record wants a sprite WA can
    -- resolve, and a missile is its own kind.
    sprite = "missile",
    worm_sprites = sb.PX_POSTURE,
    hold = hold,
    -- Route the flight sheet into the GPU atlas for the flight actor, and the
    -- zone's patch for its quad. The hold sheet comes in through `hold` itself.
    sprites = { ART .. "bullet.png", ZONE_SHEET },
    params = { gpu_prefix = ART },
    -- PX's `ExplodeAt` (:377-384), after WA's own impact (there is no injury: the
    -- record's damage and blast are 0, its bombs are the zone).
    on_explode = function(ev)
      ZONES.place(ev.x, ev.y, { healing = healing, turns = turns, owner = shooter })
    end,
  }
  -- PX's records carry "ends the turn" off (`weapons/claims.lua:46-51`), so a
  -- weapon built on one says so itself: the throw ends the turn, as WA's
  -- projectiles do.
  spec.handling = { ends_turn = true }
  wa.weapons.replace(spec)
end

return M
