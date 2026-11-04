-- Spot Hider -- Project X's zone launcher, ported to WormForge API 4 by reddaz.
--
-- PX's source is `PX_pending/weapon_zones/scripts/zone_launchers_script.txt`:
-- the missile's `ExplodeAt` branch that places the mask (:356-369), the sprite
-- it loads (:55-57), and `scripts/spot_hider_anim.txt` for the hold numbers
-- (:19-27) and the flight (:36-47). Its record is
-- `weapons/spot_hider_WEAP.wep`; the 28.09.2026 PX build has the same script
-- and record.
--
-- The weapon: the same kind of round as the two zones -- PX's record is
-- WA's standard missile (fire type 1, method 3, animation 2: a tracking
-- bazooka shell) with PX's ten-frame `spot_hider_bullet.png` drawn over it,
-- animating at `anim_speed = 0.75`. Where it lands it leaves a **mask**: PX's
-- `black_mask.png`, a soft dark blob, at `scale = 4` (:361) -- 512 pixels of a
-- 128 pixel sprite -- tinted black at `ARGB(100, 0, 0, 0)` and alpha-blended
-- (:365-366). It is a bare `CAnimation`, not a `CWZone`: it watches nothing and
-- explodes nothing (:367), it just sits there hiding what is behind it until
-- its turns run out, then fades.
--
-- Depth: PX's `ZPlane = 4.95` (:364) is the *nearest* of his four planes -- the
-- health zone's patch is 16 (:106), the Security Grenade's arrow 5 -- and the
-- mask is there to hide what is under it, so it is drawn in front of the worms
-- and the land: `wa.depth.EFFECTS`.
--
-- Lifetime: PX's `turns = 4` (:359), spent as the Blast Zone spends its turns
-- (`lib/px_zone.lua`), counted from the turn it lands in. `duration = 15`
-- (:363) is the fade after them -- PX's own note on that field is "seconds,
-- fade duration" (:255), and the zones' three-second fade is the same field.
--
-- **The shadow look** (the component's `look` option, ours, not PX's): the
-- invisible object that keeps the mask's turns carries a dark light instead
-- (`docs/fog.md`, "Darkness without fog"): an opaque darkness that fills the
-- open air from the impact point, round corners and along tunnels, until it
-- covers as much as a circle of the `radius` option (PX's mask is 256), so a
-- round landed in a pocket fills it and flows on out instead of hiding
-- nothing (`fill`). It goes on 8 pixels into the terrain it meets, then
-- fades over 8 more. It spreads out from the point over `spread_seconds`, by
-- area, so a pocket fills first and then spills, and fades with the mask's
-- fade. It is drawn as the fog draws
-- darkness, whether the match has fog or not; the weapon never turns fog on
-- or changes it. A worm touching it, where this viewer sees it more than
-- half dark, shows none of WA's HUD -- labels, arrows, the thought cloud of a
-- weapon being picked, its aim -- only the worm itself, darkened
-- (`worm.hide_hud`). With `hides_for = "enemies"` the shooter's side sees it
-- at half its darkness, so their own worms and their HUD show through.
-- Drawing only; nothing of it reaches the simulation.
--
-- Not ported, and why:
--   * `useObj` (:358) -- PX attaches the animation to an object; here the
--     object *is* the mask (`lib/px_zone.lua`'s placer);
--   * `SPEED = 25` (:362) -- this is a one-frame sprite, so PX's animation
--     frame rate never moves it;
--   * PX's own `<sh_grid.png>` and `<spot_bullet.png>` -- no script loads
--     them: the script loads only `black_mask.png` and
--     `spot_hider_bullet.png` (:6, :39).
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
    wa.log("Spot Hider: in no panel slot; nothing registered")
    return
  end

  local ART = "sprites/spot_hider/"
  local sb = require("lib/px_sprite_builder")
  local zone = require("lib/px_zone")

  -- PX's numbers (`zone_launchers_script.txt`).
  local MASK_TURNS = 4      -- `SpotHiderParams->turns = 4` (:359)
  local MASK_SPRITE = 128   -- black_mask.png is a 128 pixel sprite
  local MASK_SCALE = 4      -- `SH_scale = 4` (:31), `scale = SH_scale` (:361)
  local MASK_SIZE = MASK_SPRITE * MASK_SCALE
  local MASK_ALPHA = 100    -- `ARGB(100, 0, 0, 0)`: black at 100/255 (:365)
  local MASK_DEPTH = wa.depth.EFFECTS -- `ZPlane = 4.95`, his nearest plane (:364)
  local FADE_FRAMES = 15 * 50 -- `duration = 15` (:363) seconds of 50 frames
  local MASK_SHEET = ART .. "mask.png"

  -- PX's flight sprite is the same ten-frame sheet he draws in the hand
  -- (`spot_hider_anim.txt:19` and `:39` both name `spot_bullet`), so both use
  -- the one strip here: `sprites/spot_hider/pulse.png`.
  local PULSE_SHEET = ART .. "pulse.png"
  local PULSE_FRAMES = 10   -- `LoadSprite(f, 10, 0)` (`spot_hider_anim.txt:6`)
  local PULSE_SPEED = 0.75  -- `anim_speed = 0.75` (`spot_hider_anim.txt:42`)

  local option = function(key, default)
    local v = ctx.option and ctx.option(key)
    if v == nil then return default end
    return v
  end
  local shadow = option("look", "shadow") == "shadow"
  local enemies_only = option("hides_for", "everyone") == "enemies"
  local spread_frames = math.max(1, option("spread_seconds", 4) * 50)
  local OWN_SIDE = 128 -- what the shooter's side sees with `hides_for = "enemies"`

  -- 1 while the mask lasts, falling to 0 over PX's fade.
  local function opacity(z)
    return 1 - math.min(1, (z.fade or 0) / FADE_FRAMES)
  end

  -- The darkness the object carries: filled once to the area of `radius`'s
  -- circle (the engine fills again only when the terrain under it changes),
  -- spread out over `spread_frames` and faded with the mask. Written only
  -- when it changes; neither a spread nor a fade makes the engine fill again.
  local REACH = option("radius", MASK_SIZE // 2)
  -- On into the terrain it reaches: 8 pixels at full, then fading over 8
  -- more, so a worm dug in at a wall's face is not left in the light.
  local INTO_TERRAIN = { depth = 8, falloff = 8 }
  local function shade(z)
    local circle = math.min(REACH, REACH * z.timer // spread_frames)
    local strength = math.floor(255 * opacity(z) + 0.5)
    if circle == z.circle and strength == z.strength then return end
    z.circle, z.strength = circle, strength
    z.actor.light = {
      mode = "dark", circle = circle, reach = REACH, cone = { length = 0 },
      shadow_cast = true, seen_by = "everyone", strength = strength,
      owner_strength = enemies_only and math.floor(OWN_SIDE * opacity(z) + 0.5) or nil,
      without_fog = true,
      into_terrain = INTO_TERRAIN,
      fill = true,
    }
  end

  -- **The HUD of a worm in the dark.** Every drawn frame on each machine, by
  -- that machine's own darkness (`wa.fog.shade`): a worm with more than half
  -- of it at its centre or the edges of its body has WA's HUD over it hidden,
  -- and shown again once it is out. The shooter's side sees at most half
  -- with `hides_for = "enemies"`, so its own worms keep theirs.
  local placed = {}
  if shadow then
    local HUD = { labels = true, arrow = true, weapon = true, aim = true }
    local BODY = { { 0, 0 }, { -5, 0 }, { 5, 0 }, { 0, -7 }, { 0, 7 } }
    local HALF = 128
    local hidden = {}
    wa.on.draw(function()
      for i = #placed, 1, -1 do
        if (placed[i].fade or 0) >= FADE_FRAMES then table.remove(placed, i) end
      end
      if #placed == 0 and next(hidden) == nil then return end
      local now = {}
      if #placed > 0 then
        for _, w in ipairs(wa.worms.all()) do
          for _, p in ipairs(BODY) do
            if wa.fog.shade(w.x + p[1], w.y + p[2]) > HALF then
              now[w.id] = w
              break
            end
          end
        end
      end
      for id, w in pairs(now) do
        if not hidden[id] then w.hide_hud = HUD end
      end
      for id, w in pairs(hidden) do
        if not now[id] then w.hide_hud = false end
      end
      hidden = now
    end)
  end

  -- The thrower, PX's `ClWT`/`ClWN`: whose side `hides_for = "enemies"`
  -- leaves able to see through the darkness.
  local shooter
  wa.on.worm_message(function(worm)
    if worm.weapon == "px.spot_hider" then shooter = worm end
  end, { msgs = { wa.msg.FIRE_WEAPON } })

  -- PX's `CAnimation` with no object under it (:367), through the shared
  -- machine: no box, no clock, no payload -- only its turns and its drawing.
  local ZONES = zone.register({
    name = "Spot Hider",
    fade_frames = FADE_FRAMES,
    frame = shadow and shade or nil,
    draw = not shadow and function(z)
      local alpha = math.floor(MASK_ALPHA * opacity(z))
      zone.mark(MASK_SHEET, z.x, z.y, MASK_SIZE, 0,
        alpha << 24, "alpha", MASK_DEPTH, 0)
    end or nil,
  })

  -- **The round in flight, drawn and turned by hand.** PX's `WeapSprite` with
  -- `animate = true, anim_speed = 0.75` (`spot_hider_anim.txt:41-42`) leaves
  -- WA's sprite 0 and draws PX's ten-frame pulse on the missile, turned by the
  -- record's own animation type: `+0x64` is 2, the track-movement type
  -- (`highlander_0rang3_test/lib/missile_sprites.lua:22-25`).
  sb.flight(ctx, {
    weapon = "px.spot_hider",
    sheet = PULSE_SHEET,
    anim = "track",
    cyclical = PULSE_FRAMES,
    anim_speed = PULSE_SPEED,
    z = wa.depth.OBJECTS - 1,
    mirror = true,
  })

  -- **The worm's aim and pick art**, PX's sprite-builder split in two, with
  -- PX's own hold numbers (`spot_hider_anim.txt:20-27`): `hand_type` 1 (the
  -- lower hand), `hand_scale` 0.8, `hand_radius` 20, `hand_rotation` 1,
  -- `hand_radial_rotation` 1, `weap_radius` 10, `weap_rotation` -3,
  -- `weap_radial_rotation` 0.9. `animate` is left at `CWormAnimParams`' default
  -- of false (`worms_anims_script.txt:97`), so the hand shows frame 0 of the
  -- pulse -- `frames = 1` -- and only the flight animates.
  local hold = {
    sheet = PULSE_SHEET,
    hand = sb.PX_HANDS[1], -- hand_type 1: the lower hand
    hand_radius = 20.0,
    hand_rotation = 1.0,
    hand_radial_rotation = 1.0,
    hand_scale = 0.8,
    weap_radius = 10.0,
    weap_rotation = -3.0,
    weap_radial_rotation = 0.9,
    frames = 1,
    thrown = true,
    -- Gone on space, as PX's: no `FSprite` firing sprite, so his `sprite = 0`
    -- (`worms_anims_script.txt:263`, :419-422).
    keep_while_firing = false,
  }

  local spec = {
    -- PX's own record for this weapon, byte for byte.
    wep = "weps/spot_hider_wep.wep",
    panel_icon = ART .. "icon.png", -- PX's own (sh_ico.png)
    sprite = "missile",
    worm_sprites = sb.PX_POSTURE,
    hold = hold,
    -- The pulse serves both the flight actor and the hold; the mask is the
    -- quad the zone draws in the mask look.
    sprites = shadow and { PULSE_SHEET } or { PULSE_SHEET, MASK_SHEET },
    params = { gpu_prefix = ART },
    -- PX's `ExplodeAt` (:356-369), after WA's own impact -- and the record has
    -- nothing of its own: explosion power 0, as the two zones'.
    on_explode = function(ev)
      local z = ZONES.place(ev.x, ev.y, { turns = MASK_TURNS, owner = shooter })
      if shadow then
        shade(z)
        placed[#placed + 1] = z
      end
    end,
  }
  spec.handling = { ends_turn = true }
  wa.weapons.replace(spec)
end

return M
