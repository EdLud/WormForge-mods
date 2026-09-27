-- Highlander, on Project X's weapon layout.
--
-- A port of Project X's `scheme_hl_0rang3` (Highlander 0rang3 1.1). Every
-- worm is dealt one weapon from each of three pools at the start of the match.
-- Only the worm whose turn it is may use its weapons, one shot of each per
-- turn. Kill a worm and you take everything it carried.
--
-- The scheme puts each of its weapons on one of WA's 71 stock slots: the
-- Baseball Bat on the girder's, the Cluster Bomb on the magic bullet's, and
-- so on. The pools below are PX's own lists, in PX's order, each weapon
-- written as the stock slot it takes. A weapon not ported yet leaves WA's
-- stock weapon on its slot, and that stands in for it.
--
-- The source (`highlander.txt`) does all of this with four calls:
-- SetWeaponEx(team, weapon, 1) to grant and SetWeaponEx(team, weapon, 0) to
-- take away. `worm:ammo(name, { set = n })` is the same absolute write. It has
-- to be absolute: a stock scheme gives some of these weapons infinite ammo,
-- and adding to infinite leaves it infinite.
--
-- Where this differs from the source, on purpose:
--
--   * No turn-end removal. PX removes a worm's weapons at M_TURNEND and again,
--     through CurW, at the next M_TURNBEGIN. The second alone is enough, so
--     this listens for one message instead of two.
--
--     START_TURN (0x34) reaches only the worm whose turn it is: WA's handler
--     marks the receiver turn-active and calls TeamArena::SetActiveWorm on it
--     unconditionally (OpenWA `msg_start_turn`), which would be nonsense sent
--     to every worm. So the worm it arrives on IS the active worm.
--
--   * Every pooled slot is zeroed for every team at each turn start, not
--     just the previous worm's. PX relied on its scheme having those slots at
--     zero. Here the scheme can say anything, so the pack enforces it itself.
--
--   * PX's GiveWeapons also sets the Hot Air Balloon to 3 and the Wind
--     Changer to 1 each turn. The balloon is granted; the Wind Changer is
--     not ported yet, and its slot would hand out WA's stock Surrender.
--
-- Lockstep: dealing, turn_start and death are all dispatched from WA's own
-- simulation messages, and every random choice is wa.random(). Two peers, or
-- a peer and a replay, deal the same hands and make the same grants. Nothing
-- here reads local input or the clock.

-- ---------------------------------------------------------------- weapons

-- PX's sprite builder, for the weapons below whose hold PX draws at run
-- time: the worm posture with no weapon in it, and its hands. The helper
-- further down draws the weapon and a hand over it.
local PX_POSTURE = {
  weaponlnk = "sprites/px_hold/aim", weaponlnku = "sprites/px_hold/aimu",
  weaponlnkd = "sprites/px_hold/aimd",
  wthrow = "sprites/px_hold/draw", wthrowu = "sprites/px_hold/drawu",
  wthrowd = "sprites/px_hold/drawd",
}
local PX_HANDS = {
  "sprites/px_hold/hand_rad_lower", "sprites/px_hold/hand_rad", "sprites/px_hold/hand_rad_upper",
}
-- Ported weapons. Each takes its scheme record, cut from the .pxs with
-- tools/px_scheme_weps.py: how it fires, and its PX name. Anything else in an
-- entry goes to wa.weapons.replace as it is.
--
-- WA's own weapons, as PX tuned them for this scheme. One moved off its own
-- stock slot borrows its own stock icon.
local PORTED = {
  { weapon = "dynamite" },
  { weapon = "blow_torch" },                                   -- BlowTorch
  { weapon = "flame_thrower" },
  { weapon = "girder", panel_icon = "baseball_bat" },          -- Baseball Bat
  { weapon = "girder_pack" },                                  -- 3 Girder Pack
  { weapon = "fast_walk" },
  { weapon = "crate_spy" },
  { weapon = "crate_shower" },
  { weapon = "magic_bullet", panel_icon = "cluster_bomb" },    -- Cluster Bomb
  { weapon = "invisibility", panel_icon = "teleport" },        -- Teleport
  { weapon = "damage_x2", panel_icon = "skunk" },              -- Skunk
  { weapon = "double_turn_time", panel_icon = "mole_bomb" },   -- Mole Bomb
}

-- PX weapons that need only PX's art: its icons, copied byte for byte so
-- replays share them, and its strips split into frame folders with
-- tools/px_split_strip.py. Where PX draws the worm's hold at run time with
-- its sprite builder (p_sprite_builder), so does the pack (PX_HOLDS below).
local PX_ART = {
  { -- Burning Sheep Launcher
    weapon = "sheep_launcher",
    panel_icon = "sprites/launchers/burning_sheep_launcher_ico.png",
  },
  { -- Cow Launcher
    weapon = "mad_cow",
    panel_icon = "sprites/launchers/cow_launcher_ico.png",
  },
  { -- Old Woman Launcher. Its record is PX's but for one field: +0x34,
    -- which picks a projectile's aim sheet in WA (0x51C060), is 3 (the
    -- bazooka hold, as the Cow Launcher's) where PX has 0. WA knows 1-12
    -- only and draws no worm at all for 0.
    weapon = "old_woman",
    panel_icon = "sprites/launchers/old_woman_launcher_ico.png",
  },
  { -- Pigeon Strike
    weapon = "mail_strike",
    panel_icon = "sprites/pigeon_strike/ico_pigeonst.png",
  },
  { -- Windy Cluster: the stock cluster bomb's body, PX's bits.
    weapon = "cluster_bomb",
    panel_icon = "sprites/windy_cluster/ico_windyc.png",
    cluster = { sprite = "sprites/windy_cluster/cluster" },
  },
  { -- Super Gravedigger, and the worm holding and taking it out.
    weapon = "banana_bomb",
    panel_icon = "sprites/super_gravedigger/sgrave_ico.png",
    sprite = "sprites/super_gravedigger/flight",
    cluster = { sprite = "sprites/super_gravedigger/cluster" },
    worm_sprites = {
      weaponlnk = "sprites/super_gravedigger/aim",
      weaponlnku = "sprites/super_gravedigger/aimu",
      weaponlnkd = "sprites/super_gravedigger/aimd",
      wthrow = "sprites/super_gravedigger/draw",
      wthrowu = "sprites/super_gravedigger/drawu",
      wthrowd = "sprites/super_gravedigger/drawd",
    },
  },
  -- The next three have trails PX draws by overriding stock sprites its
  -- records point at: the Salvation Army's wsv* frames, free here because
  -- the Ferret holds that slot. sprite_overrides does the same, for the
  -- whole match. The trail art is PX's sprite_curtis_<id> libraries'.
  { -- S.M.A.R.T Bomb: its bits home, and draw their own sprite doing so.
    weapon = "mortar",
    panel_icon = "sprites/smart_bomb/smart_ico.png",
    sprite = "sprites/smart_bomb/flight",
    cluster = {
      sprite = "sprites/smart_bomb/cluster",
      homing_sprite = "sprites/smart_bomb/cluster_homing",
    },
    sprite_overrides = { wsvbd = "sprites/smart_bomb/trail" },          -- 250
    worm_sprites = {
      weaponlnk = "sprites/smart_bomb/aim",
      weaponlnku = "sprites/smart_bomb/aimu",
      weaponlnkd = "sprites/smart_bomb/aimd",
      wthrow = "sprites/smart_bomb/draw",
      wthrowu = "sprites/smart_bomb/drawu",
      wthrowd = "sprites/smart_bomb/drawd",
    },
  },
  { -- Blaster Worm
    weapon = "homing_pigeon",
    panel_icon = "sprites/blaster_worm/bworm_ico.png",
    sprite = "sprites/blaster_worm/flight",
    cluster = { sprite = "sprites/blaster_worm/cluster" },
    sprite_overrides = { wsvbu = "sprites/blaster_worm/cluster_trail" }, -- 249
    worm_sprites = {
      weaponlnk = "sprites/blaster_worm/aim",
      weaponlnku = "sprites/blaster_worm/aimu",
      weaponlnkd = "sprites/blaster_worm/aimd",
      wthrow = "sprites/blaster_worm/draw",
      wthrowu = "sprites/blaster_worm/drawu",
      wthrowd = "sprites/blaster_worm/drawd",
    },
  },
  { -- Thumper Nade
    weapon = "battle_axe",
    panel_icon = "sprites/thumper_nade/thumpern_ico.png",
    sprite = "sprites/thumper_nade/flight",
    cluster = { sprite = "sprites/thumper_nade/cluster" },
    sprite_overrides = {
      wsvg = "sprites/thumper_nade/trail",                                -- 251
      wsvgu = "sprites/thumper_nade/cluster_trail",                       -- 252
    },
    worm_sprites = {
      weaponlnk = "sprites/thumper_nade/aim",
      weaponlnku = "sprites/thumper_nade/aimu",
      weaponlnkd = "sprites/thumper_nade/aimd",
      wthrow = "sprites/thumper_nade/draw",
      wthrowu = "sprites/thumper_nade/drawu",
      wthrowd = "sprites/thumper_nade/drawd",
    },
  },
  -- Strikes keep their bomb's art 0x14 further along than a projectile
  -- does; `sprite` and `cluster.sprite` follow it there.
  { -- Thumper Nade Strike: Thumper Nades from the sky, with the Thumper
    -- Nade's own trails (the overrides above).
    weapon = "carpet_bomb",
    panel_icon = "sprites/thumper_nade/thumpernst_ico.png",
    sprite = "sprites/thumper_nade/flight",
    cluster = { sprite = "sprites/thumper_nade/cluster" },
  },
  { -- Mortar Strike: stock mortar shells, PX's trails and bits.
    weapon = "air_strike",
    panel_icon = "sprites/mortar_strike/ico_mortarst.png",
    cluster = { sprite = "sprites/mortar_strike/cluster" },
    sprite_overrides = {
      wsvclnk = "sprites/mortar_strike/trail",                             -- 466
      wsvc = "sprites/mortar_strike/cluster_trail",                        -- 260
    },
  },
  { -- Gravler: a mole bomb whose records point its dive and dig frames at
    -- the Salvation Army's wsvr*/wsvb, which PX's script overrides.
    weapon = "mole_bomb",
    panel_icon = "sprites/gravler/gravler_ico.png",
    sprite_overrides = {
      wsvr = "sprites/gravler/gravlerdive",                                -- 245
      wsvru = "sprites/gravler/gravlerdiga",                               -- 246
      wsvrd = "sprites/gravler/gravlerdigb",                               -- 247
      wsvb = "sprites/gravler/gravlerdigc",                                -- 248
    },
    worm_sprites = {
      weaponlnk = "sprites/gravler/aim",
      weaponlnku = "sprites/gravler/aimu",
      weaponlnkd = "sprites/gravler/aimd",
      wthrow = "sprites/gravler/draw",
      wthrowu = "sprites/gravler/drawu",
      wthrowd = "sprites/gravler/drawd",
    },
  },
  { -- Gravler Strike: its record points at the same four frames, so the
    -- Gravler's overrides draw it.
    weapon = "mole_squadron",
    panel_icon = "sprites/gravler/gravlerst_ico.png",
  },
  { -- Ghost Sheep: the Aqua Sheep's own sprites, overridden.
    weapon = "aqua_sheep",
    panel_icon = "sprites/ghost_sheep/ghost_sheep_ico.png",
    sprite_overrides = {
      aquashp1 = "sprites/ghost_sheep/ghstshp1",                           -- 156
      aquashp2 = "sprites/ghost_sheep/ghstshp2",                           -- 157
    },
  },
  { -- Pogo Sheep. Its bits' trail is the Blaster Worm's (249, above).
    weapon = "sheep",
    panel_icon = "sprites/pogo_sheep/psheep_ico.png",
    sprite = "sprites/pogo_sheep/flight",
    cluster = { sprite = "sprites/pogo_sheep/cluster" },
  },
  { -- Banana Express: stock banana bombs from PX's banana plane. PX's
    -- record names its plane 704, an id PX adds past WA's sprites; `plane`
    -- gives the strike the sheet instead.
    weapon = "mb_bomb",
    panel_icon = "sprites/banana_express/banana_express_ico.png",
    plane = "sprites/banana_express/plane",
  },
  { -- Real Shotgun: PX's FireFinal fires the shotgun five times per shot,
    -- five pellets in one frame, each spread by WA's own hitscan cone.
    weapon = "shotgun",
    panel_icon = "sprites/real_shotgun/real_shotgun_ico.png",
    fire_repeat = 5,
  },
  { -- Hellish Hand-Grenade: the hellish_grenade example's art on the scheme's
    -- record, which leaves the flight sprite to the slot.
    weapon = "holy_grenade",
    panel_icon = "sprites/hellish/hhh_ico.png",
    sprite = "sprites/hellish/grenade",
    worm_sprites = {
      weaponlnk = "sprites/hellish/aim",
      weaponlnku = "sprites/hellish/aimu",
      weaponlnkd = "sprites/hellish/aimd",
      wthrow = "sprites/hellish/draw",
      wthrowu = "sprites/hellish/drawu",
      wthrowd = "sprites/hellish/drawd",
    },
  },
  { -- Remote Roller
    weapon = "skunk",
    panel_icon = "sprites/remote_roller/rroller_ico.png",
    sprite = "sprites/remote_roller/flight",
    worm_sprites = {
      weaponlnk = "sprites/remote_roller/aim",
      weaponlnku = "sprites/remote_roller/aimu",
      weaponlnkd = "sprites/remote_roller/aimd",
      wthrow = "sprites/remote_roller/draw",
      wthrowu = "sprites/remote_roller/drawu",
      wthrowd = "sprites/remote_roller/drawd",
    },
  },
  { -- Igniter: PX sets the missile's own sprite to 0 and draws its bullet at
    -- run time, animated and turned to its flight (PX_WEAP_SPRITES below).
    -- WA still draws its homing missile's rocket under it for now.
    weapon = "homing_missile",
    panel_icon = "sprites/igniter/igniter_ico.png",
    worm_sprites = PX_POSTURE,
    sprites = {
      "sprites/px_hold/igniter", PX_HANDS[1], PX_HANDS[2], PX_HANDS[3], "sprites/igniter/flight",
    },
    params = { gpu_prefix = "sprites/" },
  },
  { -- Sticky Bomb: PX's record leaves the bomb's sprite 0 and PX's script
    -- draws the bomb at run time. Here the bomb is the stock grenade sprite
    -- again -- a grenade-type slot picks the worm's throw sheet from it, and
    -- 0 has none -- which the override draws as PX's bomb. The bits too.
    weapon = "grenade",
    panel_icon = "sprites/sticky_bomb/sbico.png",
    sprite = "grenade",
    cluster = { sprite = "sprites/sticky_bomb/bomb" },
    -- Stuck, the bits draw with the frames at +0x178..+0x184, which the
    -- record points at the Salvation Army's 467; PX overrides that too.
    sprite_overrides = {
      grenade = "sprites/sticky_bomb/bomb",                                -- 50
      wsvclnku = "sprites/sticky_bomb/bomb",                               -- 467
    },
    worm_sprites = PX_POSTURE,
    sprites = { "sprites/px_hold/sticky_bomb", PX_HANDS[1], PX_HANDS[2], PX_HANDS[3] },
    params = { gpu_prefix = "sprites/px_hold/" },
  },
  { -- Fire Jump: a fire punch, then a jump and a glide (below).
    weapon = "fire_punch",
    panel_icon = "sprites/fire_jump/fire_jump_ico.png",
  },
  { -- Super Drill: WA's drill, cutting a second hole each frame (below).
    weapon = "pneumatic_drill",
    panel_icon = "sprites/super_drill/ico_superdrill.png",
  },
  { -- Shadow-Bolt: the record leaves the bolt's sprite 0, and PX draws the
    -- bolt at run time, animated and turned to its flight (PX_WEAP_SPRITES
    -- below), with its trail on stock 453 (sprite_curtis_453).
    weapon = "longbow",
    panel_icon = "sprites/shadow_bolt/ico_shadowb.png",
    worm_sprites = PX_POSTURE,
    sprite_overrides = { [453] = "sprites/shadow_bolt/trail" },
    sprites = { "sprites/px_hold/shadow_bolt", "sprites/shadow_bolt/bolt" },
    params = { gpu_prefix = "sprites/" },
  },
  { -- Hot Air Balloon: WA's parachute, carried up by PX's script (below).
    weapon = "bungee",
    panel_icon = "sprites/balloon/balloon_icon.png",
    sprites = { "sprites/balloon/balloon", "sprites/balloon/basket" },
    params = { gpu_prefix = "sprites/balloon/" },
  },
  { -- Helicopter: WA's jet pack, flown by PX's script (below).
    weapon = "jet_pack",
    panel_icon = "sprites/helicopter/heli_ico.png",
    sprites = { "sprites/helicopter/flying", "sprites/helicopter/jumpin" },
    params = { gpu_prefix = "sprites/helicopter/" },
  },
  { -- Sniper Rifle: the hold drawn at run time, PX's laser sight while aiming
    -- and its own shot (below). Firing, the worm takes the snipefire poses
    -- the scheme's record names (lit by the muzzle), not WA's handgun, and
    -- the hold and laser stay up over them (PX_HOLDS).
    weapon = "handgun",
    panel_icon = "sprites/sniper_rifle/srico.png",
    worm_sprites = {
      weaponlnk = PX_POSTURE.weaponlnk, weaponlnku = PX_POSTURE.weaponlnku,
      weaponlnkd = PX_POSTURE.weaponlnkd,
      wthrow = PX_POSTURE.wthrow, wthrowu = PX_POSTURE.wthrowu, wthrowd = PX_POSTURE.wthrowd,
      weaponfire = "sprites/sniper_rifle/fire", weaponfireu = "sprites/sniper_rifle/fireu",
      weaponfired = "sprites/sniper_rifle/fired",
    },
    sprites = { "sprites/px_hold/sniper_rifle", "sprites/sniper_rifle/laser" },
    params = { gpu_prefix = "sprites/" },
  },
  { -- Burst Rifle: the worm aiming it, taking it out and firing it.
    weapon = "minigun",
    panel_icon = "sprites/burst_rifle/ico_burstr.png",
    worm_sprites = {
      weaponlnk = "sprites/burst_rifle/aim",
      weaponlnku = "sprites/burst_rifle/aimu",
      weaponlnkd = "sprites/burst_rifle/aimd",
      wthrow = "sprites/burst_rifle/draw",
      wthrowu = "sprites/burst_rifle/drawu",
      wthrowd = "sprites/burst_rifle/drawd",
      weaponfire = "sprites/burst_rifle/fire",
      weaponfireu = "sprites/burst_rifle/fireu",
      weaponfired = "sprites/burst_rifle/fired",
    },
  },
}

for _, list in ipairs({ PORTED, PX_ART }) do
  for _, w in ipairs(list) do
    local spec = { wep = "weps/" .. w.weapon .. ".wep" }
    for key, value in pairs(w) do
      spec[key] = value
    end
    wa.weapons.replace(spec)
  end
end

-- The two with a script of their own. Both run from worm messages, which WA
-- sends in lockstep on every peer and in replays.

-- Super Drill (PX weapon_super_drill): WA keeps drilling as it always does,
-- and a hidden actor cuts a second hole at the worm each frame until WA's
-- drill stops. The same as the super_drill example.
local drills = {}

local function follow_drill(worm, id)
  local started, waiting = false, 0
  return function(a)
    if worm.drilling then
      started = true
      wa.land.cut({ x = worm.x, y = worm.y, shape = "drill" })
      return
    end
    -- WA enters its drilling state a few frames after the shot.
    if not started and waiting < 4 then
      waiting = waiting + 1
      return
    end
    drills[id] = nil
    a:despawn()
  end
end

-- Fire Jump (PX Fire_Jump_script): WA's fire punch, whose speed then follows
-- PX's timeline, counted in frames from the punch -- up at once, forward
-- after half a second, a little higher at one second, and from 80 frames a
-- fall cut back to 4 pixels a frame whenever it passes 5, until 210. PX
-- speeds are pixels per frame; WA's are 16.16. See
-- docs/px-reverse-engineering.md.
--
-- PX counts from FireFinal, which WA calls only once the punch's wind-up has
-- played, not when fire is pressed. FireFinal starts the punch at -6 pixels
-- a frame; the worm stood still until then. So the count starts on the
-- first frame after fire is pressed that the worm is rising.
--
-- WA keeps the worm in its punch state until it has stopped, so the punch
-- itself cuts the way up and burns worms on it, all jump long: PX adds no cut.
local PX = 0x10000
local jumps = {}   -- worm id -> frames since the punch
local winding = {} -- worm id -> frames since fire was pressed
-- A wind-up never takes this long; give up rather than fire late.
local WIND_UP_MAX = 100

local function fire_jump(worm, t)
  if t == 1 then
    worm.vy = -9 * PX
  elseif t == 30 then
    worm.vx = worm.facing * 4 * PX
  elseif t == 60 then
    worm.vy = worm.vy - PX
  end
  if t > 80 and t < 210 and worm.vy > 5 * PX then
    worm.vy = 4 * PX
  end
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FIRE_WEAPON then
    if worm.weapon == "pneumatic_drill" and not drills[worm.id]
        and worm:ammo("pneumatic_drill") ~= 0 then
      local id = worm.id
      drills[id] = wa.actors.spawn({
        sprite = false, x = worm.x, y = worm.y,
        gravity = false, collide = false, owner = worm,
        on = follow_drill(worm, id),
      })
    elseif worm.weapon == "fire_punch" and worm:ammo("fire_punch") ~= 0 then
      winding[worm.id] = 0
    elseif worm.weapon == "handgun" and worm:ammo("handgun") ~= 0 then
      -- The Sniper Rifle's own shot, over WA's (PX's snipfiring).
      wa.sound.play(worm, "sounds/sniper_firing.wav")
    end
    -- Neither eats the shot: WA's drill and fire punch still run.
    return
  end
  if msg == wa.msg.FRAME_FINISH and winding[worm.id] then
    if worm.vy < 0 then
      winding[worm.id], jumps[worm.id] = nil, 0
    else
      local w = winding[worm.id] + 1
      winding[worm.id] = w < WIND_UP_MAX and w or nil
    end
  end
  if msg == wa.msg.FRAME_FINISH and jumps[worm.id] then
    local t = jumps[worm.id] + 1
    fire_jump(worm, t)
    jumps[worm.id] = t < 211 and t or nil
  end
end)

-- ------------------------------------------ PX's sprite builder, at run time
--
-- PX draws many weapons' holds at run time (p_sprite_builder, WormSprite).
-- Over a worm posture with no weapon in it -- def_shot_aim_*, the sheets
-- below -- it draws the weapon and a hand, each placed and turned from the
-- aim angle by the weapon's CWormAnimParams, and grows the weapon in over the
-- first 20 frames of aiming. This does the same with two actors per aiming
-- worm, from worm messages, so in lockstep.
--
-- It reads worm.aim (the aim WA draws, 0 straight down .. 1 straight up:
-- PX's FireAngle) and worm.aiming (WA draws the worm with its weapon out:
-- PX's WS_AIMING or WS_SETPOWER). On an engine without them it does
-- nothing.

-- In front of worms and terrain, as the sentry's gun.
local HOLD_DEPTH = 0x10000

-- WormSprite's grow-in, counter 0..20: to 2.7 * c/20 up to 9, then 0.025
-- smaller a frame, then 0.9, 0.95, and full size from 20.
local PICK = {}
do
  local s = 0
  for c = 0, 20 do
    if c >= 20 then s = 1
    elseif c > 17 then s = c / 20
    elseif c > 9 then s = s - 0.025
    else s = 2.7 * c / 20 end
    PICK[c] = s
  end
end

-- Slot -> the weapon's CWormAnimParams, as its PX script states them.
local PX_HOLDS = {
  grenade = { -- Sticky Bomb (sb_script)
    -- Thrown: once fired it has left the worm's hands, and WA puts nothing
    -- away (as for its own grenades), so neither does the rule.
    thrown = true,
    sheet = "sprites/px_hold/sticky_bomb", hand_type = 1, hand_radius = 24,
    hand_rotation = 1.0, hand_radial_rotation = 1.05, hand_scale = 0.8,
    weap_rotation = 0.5, weap_radial_rotation = 0.9, weap_radius = 10,
  },
  homing_missile = { -- Igniter (igniter_anim)
    -- Up through the shot too: it has no firing poses of its own, so WA
    -- fires it in the aim posture, empty-handed without the hold. Not PX's.
    keep_while_firing = true,
    sheet = "sprites/px_hold/igniter", hand_type = 2, hand_radius = -6.0,
    hand_rotation = 1.0, hand_radial_rotation = 0.9, hand_scale = 0.8,
    weap_rotation = 1.0, weap_radial_rotation = 0.0, weap_radius = 0.0,
  },
  handgun = { -- Sniper Rifle (sniper_rifle_script): its hand at scale 0
    -- Up through each shot, with its laser, over the snipefire poses (the
    -- worm lit by the muzzle), so it does not flicker between the three.
    -- Not PX's: PX hides it until the worm aims again.
    keep_while_firing = true,
    sheet = "sprites/px_hold/sniper_rifle", draw_hand = false, hand_radius = -6.0,
    hand_rotation = 1.0, hand_radial_rotation = 0.9,
    weap_rotation = 1.0, weap_radial_rotation = 0.0, weap_radius = 0.1,
  },
  longbow = { -- Shadow-Bolt (shadow_bolt_script): no hand, the bolt animated
    -- The crossbow stays up through the shot: it has no firing poses of
    -- its own, so WA fires it in the aim posture. Not PX's.
    keep_while_firing = true,
    sheet = "sprites/px_hold/shadow_bolt", draw_hand = false, hand_radius = 0.0,
    hand_rotation = 0.0, hand_radial_rotation = 0.0,
    weap_rotation = 1.0, weap_radial_rotation = 0.0, weap_radius = 3.5,
    animate = true, anim_speed = 1.30, frames = 6,
  },
}

-- WormSprite::CalculateFrame and WeapSprite::CalculateFrame: a phase from 0
-- to 1 through the sheet, anim_speed * 0.03 a frame, back to 0 past 0.99.
local function next_phase(phase, anim_speed)
  if phase > 0.99 then
    return 0
  end
  return phase + anim_speed * 30 / 1000
end

local function frame_of(phase, frames)
  return math.min(math.floor(phase * frames), frames - 1)
end

local held = {} -- worm id -> { slot, weapon, hand, counter, phase, aim }

local function drop_hold(id)
  local h = held[id]
  if h then
    h.weapon:despawn()
    if h.hand then
      h.hand:despawn()
    end
    held[id] = nil
  end
end

-- One sprite of the hold: centred at (dx, dy) pixels from the worm, turned
-- by `angle` radians, as PX computes them for a worm facing right; facing
-- left mirrors all three, as PX's left-facing formulas do.
local function place(a, worm, dx, dy, angle, scale)
  local f = worm.facing
  -- Positions are 16.16 integers.
  a.x = worm.x + math.floor(f * dx * 0x10000 + 0.5)
  a.y = worm.y + math.floor(dy * 0x10000 + 0.5)
  a.vx, a.vy = 0, 0
  a.facing = f
  a:gfx({ angle = math.deg(angle * f) % 360, scale = scale, depth = HOLD_DEPTH })
end

-- worm.aim, or nil on an engine without it: a worm has no such field there,
-- and reading one is an error rather than nil.
local function aim_of(worm)
  local ok, aim = pcall(function() return worm.aim end)
  return ok and aim or nil
end

local function spawn_hold(worm, slot)
  local p = PX_HOLDS[slot]
  local function actor(sheet)
    return wa.actors.spawn({
      sprite = sheet, x = worm.x, y = worm.y, gravity = false,
      collide = false, owner = worm, on = function() end,
    })
  end
  local h = { slot = slot, counter = 0, phase = 0, weapon = actor(p.sheet) }
  -- A weapon PX draws with no hand: draw_hand = false.
  if p.draw_hand ~= false then
    h.hand = actor(PX_HANDS[p.hand_type])
  end
  held[worm.id] = h
  return h
end

-- WormSprite::CalculateAngle: the hold at its aim, grown to PICK[counter].
local function place_hold(worm, h)
  local p = PX_HOLDS[h.slot]
  local aim = h.aim
  local pi = math.pi
  local rot = (1 - aim) * pi
  local rot_w = rot + pi * p.weap_radial_rotation
  local rot_h = rot - pi * p.hand_radial_rotation
  local grow = PICK[h.counter]
  place(h.weapon, worm, math.sin(rot_w) * p.weap_radius, -math.cos(rot_w) * p.weap_radius,
    pi - pi * aim - pi * (1 - p.weap_rotation), grow)
  if p.animate then
    h.phase = next_phase(h.phase, p.anim_speed)
    h.weapon:frame(frame_of(h.phase, p.frames))
  end
  if h.hand then
    place(h.hand, worm, math.sin(rot_h) * p.hand_radius, -math.cos(rot_h) * p.hand_radius,
      rot + pi * p.hand_rotation, grow * p.hand_scale)
  end
end

-- Putting a weapon away. Not PX's: PX drops the hold the frame the worm
-- stops aiming. WA puts a weapon away by playing the worm's draw sheet
-- backwards, standing, over 20 frames; after a gun's last shot it has
-- already selected the next weapon. So a hold last aimed (`put_away`
-- remembers it) comes back when the worm stands with another weapon, and
-- shrinks out along the grow-in played backwards, a step a frame.
local put_away = {} -- worm id -> { slot, aim } of the hold last aimed

local function update_put_away(worm)
  local h = held[worm.id]
  if h and h.putting_away then
    if worm.state ~= "standing" or h.counter == 0 then
      drop_hold(worm.id)
      return
    end
    h.counter = h.counter - 1
    place_hold(worm, h)
    return
  end
  local last = put_away[worm.id]
  local state = worm.state
  if last and worm.aiming then
    -- Aiming another weapon: this one was never put away here.
    put_away[worm.id] = nil
    return
  end
  if not last or state == nil then
    -- No name: WA's firing states between the last aim and the put-away.
    return
  end
  put_away[worm.id] = nil
  if state == "standing" and worm.weapon ~= last.slot then
    h = spawn_hold(worm, last.slot)
    h.aim, h.counter, h.putting_away = last.aim, 20, true
    place_hold(worm, h)
  end
end

local function update_hold(worm)
  local p = PX_HOLDS[worm.weapon]
  local aim = p and aim_of(worm)
  if not aim or not worm.aiming then
    local h = held[worm.id]
    -- Fired, in WA's firing states (no state name) with the weapon still
    -- selected. Walking is unnamed too, hence the fire key.
    if h and h.firing and PX_HOLDS[h.slot].keep_while_firing and worm.state == nil
        and worm.weapon == h.slot then
      h.shot_out = true
      place_hold(worm, h)
      return
    end
    if h and not h.putting_away then
      if not (h.firing and PX_HOLDS[h.slot].thrown) then
        put_away[worm.id] = { slot = h.slot, aim = h.aim }
      end
      drop_hold(worm.id)
    end
    update_put_away(worm)
    return
  end
  put_away[worm.id] = nil
  local h = held[worm.id]
  if h and (h.slot ~= worm.weapon or h.putting_away) then
    drop_hold(worm.id)
    h = nil
  end
  h = h or spawn_hold(worm, worm.weapon)
  -- Kept for anything drawn with the hold (the Sniper Rifle's laser), so it
  -- turns with the weapon: worm.aim is WA's smoothed crosshair (+0x270),
  -- which WA also rewrites at render time, between sim frames.
  -- The wind-up after the fire key still counts as aiming; the shot is
  -- over only once the worm aims again after WA's firing states.
  if h.shot_out then
    h.firing, h.shot_out = false, false
  end
  h.aim = aim
  place_hold(worm, h)
  h.counter = math.min(h.counter + 1, 20)
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FIRE_WEAPON and held[worm.id] then
    held[worm.id].firing = true
  end
  if msg == wa.msg.FRAME_FINISH then
    update_hold(worm)
  end
end)

-- ------------------------------------------ the Sniper Rifle's laser sight
--
-- PX's LaserSight (weapon_gun_sniper_rifle_sb, on utility_laser_pointer's
-- laserray): while the current worm aims the rifle, a red ray from 12 pixels
-- out along the aim to the first thing in its way, drawn every rendered
-- frame as 100-pixel quads of laser.png, added to the scene, narrowing along
-- the ray, with a faint 7-pixel tip. It is drawing only: wa.on.draw, never
-- the simulation.

local LASER_LEN = 15000
local LASER_WIDTH = 2
local LASER_STEP = 5 -- PX's Trace tests every 5 pixels
-- PX starts the ray on the worm's centre line, but the rifle art's barrel
-- runs 2 pixels to its left (columns 26-29 of 60), so the ray ran that far
-- under the barrel. It starts on the barrel instead.
local LASER_BARREL = 2
local function argb(a, r, g, b)
  return ((a * 256 + r) * 256 + g) * 256 + b
end
local LASER_RED, LASER_START, LASER_TIP =
  argb(255, 255, 48, 48), argb(192, 255, 96, 96), argb(16, 255, 48, 48)
-- PX's Trace stops at anything its 2x2 mask touches. Terrain is traced
-- exactly; objects by these radii in pixels, an estimate of their masks.
local STOPPERS = { { wa.worms, 6 }, { wa.mines, 4 }, { wa.crates, 10 }, { wa.oil, 9 } }

local function laser_length(x, y, dx, dy, shooter)
  local P = 0x10000
  local len = LASER_LEN
  local hit = wa.land.trace(math.floor(x), math.floor(y),
    math.floor(x + dx * LASER_LEN * P), math.floor(y + dy * LASER_LEN * P))
  if hit then
    len = math.sqrt(((hit.x - x) / P) ^ 2 + ((hit.y - y) / P) ^ 2)
  end
  for _, s in ipairs(STOPPERS) do
    local list, r = s[1], s[2]
    if list and list.all then
      for _, o in ipairs(list.all()) do
        if o.id ~= shooter then
          local ox, oy = (o.x - x) / P, (o.y - y) / P
          local t = ox * dx + oy * dy
          if t > 0 and t < len and math.abs(ox * dy - oy * dx) < r then
            len = t
          end
        end
      end
    end
  end
  return math.floor(len / LASER_STEP) * LASER_STEP
end

-- laserray's MakeLaserRayF, point for point.
local function laser_ray(x, y, ang, len)
  local P = 0x10000
  local rdx, rdy = math.sin(ang - 1.57), -math.cos(ang - 1.57)
  local dx, dy = math.sin(ang), -math.cos(ang)
  local tx, ty = x, y
  local nparts = math.floor(len / 100)
  local w = (wa.draw.random() / 4 + 0.85) * LASER_WIDTH / 2
  local wdx, wdy = w * rdx * P, w * rdy * P
  local wscale = 1
  local lastl = len - nparts * 100
  local colors
  for i = 0, nparts do
    local l = i == nparts and lastl or 100
    if l <= 0 then break end
    local p0, p3 = { tx + wdx, ty + wdy }, { tx - wdx, ty - wdy }
    w = wscale * (wa.draw.random() / 3 + 0.82) * LASER_WIDTH
    wdx, wdy = w * rdx * P, w * rdy * P
    wscale = wscale - 0.75 / (nparts + 1)
    local ex, ey = tx + dx * l * P, ty + dy * l * P
    colors = { LASER_RED, LASER_RED, LASER_RED, LASER_RED }
    if i == 0 then
      colors[1], colors[4] = LASER_START, LASER_START
    end
    wa.draw.quad({
      points = { p0, { ex + wdx, ey + wdy }, { ex - wdx, ey - wdy }, p3 },
      colors = colors, sprite = "sprites/sniper_rifle/laser", blend = "add",
    })
    tx, ty = ex, ey
  end
  local ex, ey = tx + dx * 7 * P, ty + dy * 7 * P
  wa.draw.quad({
    points = { { tx + wdx, ty + wdy }, { ex + wdx, ey + wdy }, { ex - wdx, ey - wdy }, { tx - wdx, ty - wdy } },
    colors = { LASER_RED, LASER_TIP, LASER_TIP, LASER_RED },
    sprite = "sprites/sniper_rifle/laser", blend = "add",
  })
end

if wa.on.draw then
  wa.on.draw(function()
    for _, worm in ipairs(wa.worms.all()) do
      -- The aim the rifle was drawn with, so the ray leaves along it; while
      -- the worm aims or fires the rifle, not while it puts it away.
      local h = worm.turn and held[worm.id]
      local aim = h and h.slot == "handgun" and not h.putting_away and h.aim
      if aim then
        local ang = (1 - aim) * 3.14159
        if worm.facing < 0 then
          ang = 6.28318 - ang
        end
        local P = 0x10000
        -- The art's left, turned with the aim and mirrored with the worm.
        local side = LASER_BARREL * worm.facing * P
        local x = worm.x + math.sin(ang) * 12 * P - math.cos(ang) * side
        local y = worm.y - math.cos(ang) * 12 * P - math.sin(ang) * side
        laser_ray(x, y, ang, laser_length(x, y, math.sin(ang), -math.cos(ang), worm.id))
      end
    end
  end)
end

-- ------------------------------------ PX's missile sprites, at run time
--
-- For some weapons PX draws the missile itself (p_sprite_builder,
-- WeapSprite) and leaves WA's sprite 0: a sprite that follows the missile,
-- turned to its flight, mirrored when it flies left, and, if `animate`,
-- stepped through its sheet as a hold is. Here it is a GPU actor per
-- missile, placed from wa.on.missile_frame after WA has moved the missile.
-- It reads m.weapon (the missile's slot); on an engine without it nothing
-- matches and nothing is drawn.

-- Slot -> the weapon's WeapSpriteParams, as its PX script states them.
local PX_WEAP_SPRITES = {
  longbow = { -- Shadow-Bolt
    sheet = "sprites/shadow_bolt/bolt", animate = true, anim_speed = 1.30, frames = 6,
  },
  homing_missile = { -- Igniter (igniter_anim: igniter_bullet, 16 frames)
    sheet = "sprites/igniter/flight", animate = true, anim_speed = 1.0, frames = 16,
  },
}

local flying = {} -- missile id -> { actor, phase, seen }

-- The actor goes when its missile stops reporting: WA has freed it.
local function follow_missile(id)
  return function(a)
    local f = flying[id]
    if f and f.seen then
      f.seen = false
      return
    end
    if f and f.actor == a then
      flying[id] = nil
    end
    a:despawn()
  end
end

-- The worm whose turn it is: WeapSprite's owner (GetCurrentWorm()). A
-- missile frame gives no spawn owner of its own.
local function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then
      return w
    end
  end
end

wa.on.missile_frame(function(m)
  local p = m.phase == "post" and PX_WEAP_SPRITES[m.weapon]
  if not p then
    return
  end
  local f = flying[m.id]
  if not f then
    local owner = current_worm()
    if not owner then
      return
    end
    f = { phase = 0 }
    f.actor = wa.actors.spawn({
      sprite = p.sheet, x = m.x, y = m.y, gravity = false, collide = false,
      owner = owner, on = follow_missile(m.id),
    })
    flying[m.id] = f
  end
  f.seen = true
  local a = f.actor
  a.x, a.y, a.vx, a.vy = m.x, m.y, 0, 0
  a.facing = m.vx < 0 and -1 or 1
  if p.animate then
    f.phase = next_phase(f.phase, p.anim_speed)
    a:frame(frame_of(f.phase, p.frames))
  end
  -- WeapSprite::CalculateAngle, rotation 0.
  local rot = -math.atan(m.vx, m.vy) - math.pi
  a:gfx({ angle = math.deg(rot) % 360, depth = HOLD_DEPTH })
end)

-- -------------------------------------------------------------- Helicopter
--
-- PX's helicopter_user_script, on WA's jet pack. While the jet pack runs,
-- the script flies the worm itself from the worm's own move keys, which it
-- then consumes so WA's jet pack neither thrusts nor burns fuel: speed that
-- builds while a key is held and dies away when it is not, fuel that burns
-- with it (not during retreat), and a crash -- an explosion sized by the fuel
-- left and the speed -- when the fuel runs out, the worm reaches water, the
-- turn ends, or it hits something other than a mine faster than a pixel a
-- frame, the ground included: landing slower than that is PX's smooth
-- landing. The worm's body is hidden behind the helicopter, and behind PX's
-- climb-in animation while WA winds the jet pack up; its labels, the fuel
-- counter among them, stay, as with PX's RenderWorm override.
--
-- PX's speeds and factors are fixed point: 1.0 is 0x10000 here, and its
-- arithmetic truncates.

local HELI_FUEL = 100            -- FuelAmount
local HELI_REALISTIC = true      -- gravity and wind act on it, at 0.2
local HELI_EXPLODE_ON_TURN_END = true
local HELI_DEPTH = 0x10000       -- in front of worms and terrain
local FX = 0x10000

local helis = {} -- worm id -> { flying, launch, jumpin, jump_phase, frame, ticks, body, climb }

local function trunc(v)
  return v >= 0 and math.floor(v) or math.ceil(v)
end

local function heli_of(worm)
  local h = helis[worm.id]
  if not h then
    h = { flying = false, launch = false, jumpin = false, jump_phase = 0, frame = 0, ticks = 0 }
    helis[worm.id] = h
  end
  return h
end

local function heli_actor(worm, sheet)
  return wa.actors.spawn({
    sprite = sheet, x = worm.x, y = worm.y, gravity = false,
    collide = false, owner = worm, on = function() end,
  })
end

local function heli_drop_art(h, worm)
  if h.body then h.body:despawn(); h.body = nil end
  if h.climb then h.climb:despawn(); h.climb = nil end
  worm.body_visible = true
end

local HELI_OOPS = {
  [2] = "sounds/helicopter/oops1.wav", [4] = "sounds/helicopter/oops2.wav",
  [6] = "sounds/helicopter/huh.wav", [8] = "sounds/helicopter/poop.wav",
  [10] = "sounds/helicopter/idiot.wav",
}

-- DisableHeli: blow up, sized by the fuel left and the speed, and land.
local function heli_crash(worm, h, sx, sy)
  if not h.flying then
    return
  end
  local speed = (math.abs(sy) + math.abs(sx)) / 2 / FX
  local size = trunc((worm.fuel / FX - 75) / 10 * speed)
  if size < 10 then size = 10 end
  -- The worm's own explosion: a spawn needs an owner, and outside a brain
  -- (from wa.on.contact) there is none to inherit.
  wa.actors.spawn({
    sprite = false, x = worm.x, y = worm.y, gravity = false, collide = false,
    owner = worm, explode = { damage = size * 2, id = size, now = true },
  })
  worm.gravity = FX
  worm.wind = 0
  local oops = HELI_OOPS[wa.random(1, 10)]
  if oops then wa.sound.play(worm, oops) end
  h.flying = false
  heli_drop_art(h, worm)
end

-- One of PX's key responses, towards `dir` (-1 up or left, 1 down or
-- right): a kick that fades as the speed that way reaches 10 pixels a frame.
-- PX: if (SpY > -1) SpY -= 0.2; if (SpY > -4) SpY -= 0.4; ... for up.
local function push(v, dir)
  local s = -dir * v
  if s > -1 * FX then s = s - 0.2 * FX end
  if s > -4 * FX then s = s - 0.4 * FX end
  if s > -8 * FX then s = s - 0.15 * FX end
  if s > -10 * FX then s = s - 0.05 * FX end
  return -dir * s
end

local function heli_frame(worm)
  local h = helis[worm.id]
  local state = worm.state
  -- WS_FIRED: WA winding up the Helicopter; PX shows its climb-in. This is
  -- also where it is armed: once it fires, WA may already have cleared the
  -- worm's selection (its last shot of the Helicopter), and PX decides at
  -- FireFinal, from the weapon actually fired.
  if worm.weapon == "jet_pack" and state == "prefiring" and not (h and h.flying) then
    h = heli_of(worm)
    h.jumpin, h.armed = true, true
    h.jump_phase = h.jump_phase + 0.047
  end
  -- FireFinal: the jet pack it wound up has started.
  if h and h.armed and state == "jetpacking" and not h.flying then
    worm.gravity = HELI_REALISTIC and trunc(0.2 * FX) or 0
    h.flying, h.launch, h.ticks, h.armed = true, true, 0, false
  elseif h and h.armed and not worm.turn then
    h.armed = false -- the turn ended before it fired
  end
  if not h then
    return
  end
  if h.flying then
    local vx, vy = worm.vx, worm.vy
    -- Rotor and radio, while it moves.
    if vx ~= 0 or vy ~= 0 then
      if h.ticks % 47 == 0 then wa.sound.play(worm, "sounds/helicopter/helicopterloop.wav") end
      local radio = wa.random(1, 200)
      if radio % 20 == 0 and radio <= 80 then
        wa.sound.play(worm, "sounds/helicopter/" .. (radio // 20) .. ".wav")
      end
    end
    h.ticks = h.ticks + 1
    if worm.y >= wa.world.water() then
      heli_crash(worm, h, vx, vy)
      return
    end
    if h.launch then
      worm.fuel = HELI_FUEL * FX
      h.jump_phase, h.jumpin, h.launch = 0, false, false
      if HELI_REALISTIC then worm.wind = trunc(0.2 * FX) end
    end
    local k = worm.keys
    local up, down, left, right = k.up, k.down, k.left, k.right
    if not up and not down then vy = vy / 1.105 end
    if not left and not right then vx = vx / 1.105 end
    if up and down then vy = vy / 1.095 end
    if left and right then vx = vx / 1.095 end
    -- Diagonals: PX's lines damp each pair twice.
    for _, d in ipairs({ { up, right }, { up, left }, { down, right }, { down, left } }) do
      if d[1] and d[2] then
        vx, vy = vx * 0.99 * 0.99, vy * 0.99 * 0.99
      end
    end
    h.frame = (h.frame + 1) % 3
    local fuel = worm.fuel
    local burn = wa.world.retreat() == 0
    if burn then fuel = fuel - 0.020 * FX end
    local shift = wa.world.keys().sprint
    if up then
      if burn then fuel = fuel - 0.2 * FX end
      vy = push(vy, -1)
    end
    if down then
      if burn then fuel = fuel - 0.020 * FX end
      vy = push(vy, 1)
    end
    if left then
      if burn then fuel = fuel - 0.1 * FX end
      if not shift then worm.facing = -1 end
      vx = push(vx, -1)
    end
    if right then
      if burn then fuel = fuel - 0.1 * FX end
      if not shift then worm.facing = 1 end
      vx = push(vx, 1)
    end
    worm:clear_keys()
    worm.vx, worm.vy, worm.fuel = trunc(vx), trunc(vy), trunc(fuel)
    if worm.state ~= "jetpacking" then
      if worm.vy == 0 and state ~= "prefiring" and state ~= "teleporting" then
        worm:set_state("sliding")
      end
      worm.gravity, worm.wind = FX, 0
      h.flying = false
      heli_drop_art(h, worm)
      return
    elseif worm.fuel <= 0.1 * FX then
      heli_crash(worm, h, worm.vx, worm.vy)
      return
    end
    if HELI_EXPLODE_ON_TURN_END and not worm.turn then
      heli_crash(worm, h, worm.vx, worm.vy)
      return
    end
  end
  -- What PX draws in the worm's place.
  local f = worm.facing
  if h.flying then
    if h.climb then h.climb:despawn(); h.climb = nil end
    h.body = h.body or heli_actor(worm, "sprites/helicopter/flying")
    local a = h.body
    a.x, a.y, a.vx, a.vy, a.facing = worm.x, worm.y, 0, 0, f
    a:frame(h.frame)
    a:gfx({ angle = math.deg(math.sin(worm.vx / FX / 24)) % 360, depth = HELI_DEPTH })
    worm.body_visible = false
  elseif h.jumpin and state == "prefiring" then
    h.climb = h.climb or heli_actor(worm, "sprites/helicopter/jumpin")
    local a = h.climb
    a.x = worm.x + trunc((f > 0 and -11.5 or 12.5) * FX)
    a.y, a.vx, a.vy, a.facing = worm.y + FX, 0, 0, f
    a:frame(math.min(math.floor(h.jump_phase * 23), 22))
    a:gfx({ depth = HELI_DEPTH })
    worm.body_visible = false
  elseif h.body or h.climb then
    h.jumpin, h.jump_phase = false, 0
    heli_drop_art(h, worm)
  end
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FRAME_FINISH then
    heli_frame(worm)
  end
end)

-- Collide: hitting anything but a mine faster than a pixel a frame crashes
-- it, the ground included -- a slow landing is PX's smooth landing -- judged
-- on the speed before WA exchanged velocities.
if wa.on.contact then
  wa.on.contact(function(worm, other, c)
    local h = helis[worm.id]
    if h and h.flying and other.kind ~= "mine"
        and (math.abs(c.vx) > FX or math.abs(c.vy) > FX) then
      heli_crash(worm, h, c.vx, c.vy)
    end
  end)
end

-- --------------------------------------------------------- Hot Air Balloon
--
-- PX's balloon_s (r2_balloon by rafa''2, modified by 0rang3), on WA's
-- parachute. While the parachute is open, the worm's gravity is turned
-- upside down, so it rises; the balloon pops -- gravity back -- when the
-- parachute closes, at a turn change, or in water. The worm's body is
-- hidden behind the balloon, drawn in its team's colour, and the worm in its
-- basket, as PX's RenderWorm override draws them.

local BALLOON_DEPTH = 0x10001    -- behind the basket, in front of worms
local BASKET_DEPTH = 0x10000
-- PX's GetTeamColorRGB, by WA's colour index (worm.alliance, 0 red .. 5 cyan).
-- PX adds it to its dark grey balloon (SetColorMod mode 8); the GPU tint
-- multiplies, so the pack's balloon art is PX's lightened to white, and the
-- team colour shows at full strength.
local TEAM_RGB = { 0xFF8080, 0x0096FF, 0x00D000, 0xFFFF40, 0xE800E8, 0x50FFFF }

local balloons = {} -- worm id -> { active, gravity, ticks, last_weapon, balloon, basket }

local function balloon_of(worm)
  local b = balloons[worm.id]
  if not b then
    b = { active = false, gravity = 0, ticks = 0 }
    balloons[worm.id] = b
  end
  return b
end

local function balloon_sound(worm, name, n)
  wa.sound.play(worm, "sounds/balloon/" .. name .. wa.random(1, n) .. ".wav")
end

-- StopBalloon: gravity back, and a pop.
local function balloon_stop(worm, b)
  if not b.active then
    return
  end
  worm.gravity = -b.gravity
  b.active, b.ticks = false, 0
  if b.balloon then b.balloon:despawn(); b.balloon = nil end
  if b.basket then b.basket:despawn(); b.basket = nil end
  worm.body_visible = true
  balloon_sound(worm, "pop", 4)
end

local function balloon_frame(worm)
  local b = balloon_of(worm)
  local state = worm.state
  -- FireFinal(Hot Air Balloon): WA opens its parachute straight away and
  -- clears the selection as it does ("none"), so it is the one the worm had
  -- the frame before.
  local weapon = worm.weapon
  if weapon == nil or weapon == "none" then
    weapon = b.last_weapon
  end
  if not b.active and state == "parachuting" and not b.was_parachuting
      and weapon == "bungee" then
    b.active, b.ticks = true, 0
    balloon_sound(worm, "inflate", 3)
  end
  b.was_parachuting = state == "parachuting"
  b.last_weapon = worm.weapon
  if b.active then
    if state == "parachuting" and worm.turn and worm.y < wa.world.water() then
      worm.gravity = b.gravity
    else
      if state == "standing" then
        worm:set_state("sliding")
      end
      balloon_stop(worm, b)
      return
    end
    b.ticks = b.ticks + 1
    -- DrawBalloonWorm: the balloon above, in the team's colour, and the worm
    -- in its basket, whose art faces left.
    local f = worm.facing
    local function art(sheet)
      return wa.actors.spawn({
        sprite = sheet, x = worm.x, y = worm.y, gravity = false,
        collide = false, owner = worm, on = function() end,
      })
    end
    b.balloon = b.balloon or art("sprites/balloon/balloon")
    b.basket = b.basket or art("sprites/balloon/basket")
    local x = worm.x + 6 * f * FX
    b.balloon.x, b.balloon.y, b.balloon.vx, b.balloon.vy = x, worm.y - 43 * FX, 0, 0
    b.balloon:frame(math.min((b.ticks % 200) * 16 // 200, 15))
    b.balloon:gfx({ tint = 0xFF000000 | (TEAM_RGB[(worm.alliance or 0) + 1] or 0xFFFFFF),
      depth = BALLOON_DEPTH })
    b.basket.x, b.basket.y, b.basket.vx, b.basket.vy = x, worm.y + 3 * FX, 0, 0
    b.basket.facing = -f
    b.basket:frame(math.min((b.ticks % 80) * 17 // 80, 16))
    b.basket:gfx({ depth = BASKET_DEPTH })
    worm.body_visible = false
  else
    -- Kept up to date while it is not flying: the gravity to turn over.
    b.gravity = -worm.gravity
  end
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FRAME_FINISH then
    balloon_frame(worm)
  end
end)

-- M_TURNBEGIN: any balloon still up pops.
wa.on.turn_start(function()
  for _, worm in ipairs(wa.worms.all()) do
    local b = balloons[worm.id]
    if b and b.active then
      balloon_stop(worm, b)
    end
  end
end)

-- ----------------------------------------------------------------- pools

-- Offensive: PX's `Weapons`, 29 entries.
local OFFENSIVE = {
  "bazooka",          -- Double Bazooka
  "homing_missile",   -- Igniter
  "mortar",           -- S.M.A.R.T Bomb
  "homing_pigeon",    -- Blaster Worm
  "sheep_launcher",   -- Burning Sheep Launcher
  "grenade",          -- Sticky Bomb
  "cluster_bomb",     -- Windy Cluster
  "banana_bomb",      -- Super Gravedigger
  "battle_axe",       -- Thumper Nade
  "earthquake",       -- Electric Grenade
  "dynamite",         -- Dynamite
  "mine",             -- Nuke Rocket
  "sheep",            -- Pogo Sheep
  "aqua_sheep",       -- Ghost Sheep
  "super_banana",     -- Chilli Bomb
  "holy_grenade",     -- Hellish Hand-Grenade
  "petrol_bomb",      -- Valyrian Fire
  "skunk",            -- Remote Roller
  "ming_vase",        -- Priceless Ming Vase
  "mad_cow",          -- Cow Launcher
  "old_woman",        -- Old Woman Launcher
  -- Not dealt on cavern maps:
  "salvation_army",   -- Ferret
  "air_strike",       -- Mortar Strike
  "mail_strike",      -- Pigeon Strike
  "mine_strike",      -- Submarine Attack
  "mole_squadron",    -- Gravler Strike
  "mb_bomb",          -- Banana Express
  "sheep_strike",     -- Bowling Ball Strike
  "carpet_bomb",      -- Thumper Nade Strike
}

-- Second weapon: PX's `NotWeapons`, 19 entries.
local SECOND = {
  "fire_punch",         -- Fire Jump
  "dragon_ball",        -- Sentry Laser
  "kamikaze",           -- Sentry Gun
  "prod",               -- Javelin
  "girder",             -- Baseball Bat
  "baseball_bat",       -- Electromagnet
  "shotgun",            -- Real Shotgun
  "handgun",            -- Sniper Rifle
  "uzi",                -- Laser Gun
  "minigun",            -- Burst Rifle
  "longbow",            -- Shadow-Bolt
  "blow_torch",         -- BlowTorch
  "pneumatic_drill",    -- Super Drill
  "scales_of_justice",  -- Portal Gun
  "armageddon",         -- Ice Arrow
  "flame_thrower",      -- Flame Thrower
  -- Not dealt on cavern maps:
  "nuclear_test",       -- Reinforcement
  "donkey",             -- Crate Strike
  "napalm_strike",      -- Lightning Strike
}

-- Movement: PX's `MoveWeapons`, 7 entries, all dealt on every map.
local MOVEMENT = {
  "girder_pack",   -- 3 Girder Pack
  "ninja_rope",    -- Jump
  "parachute",     -- Hang-Glider
  "teleport",      -- Super Tele
  "jet_pack",      -- Helicopter
  "low_gravity",   -- Gravity Control
  "laser_sight",   -- Swim Suit
}

-- On cavern maps PX draws RandomInt(0,20) and RandomInt(0,15) instead of the
-- whole lists: the first 21 offensive and first 16 second weapons. What that
-- leaves out is what comes from the sky, plus the Ferret.
local CAVE_OFFENSIVE = 21
local CAVE_SECOND = 16

-- The slots Highlander never pools -- Kamikaze Rocket, Gravler, Hot Air
-- Balloon, Skip Go/Surrender, Wind Changer, Muahaha 3, Weapon Crate, Cluster
-- Bomb, Fast Walk, Teleport, Skunk, Crate Spy, Mole Bomb, Crate Shower -- keep
-- whatever ammo the scheme gives them, except the Hot Air Balloon, which
-- start_turn sets to 3.

-- Every slot this pack owns, in a fixed order. Zeroing walks this list, so it
-- must not depend on pairs() order: Lua's string hashing is seeded per
-- process, and a different order on each peer is a different sequence of
-- writes.
local POOLED = {}
for _, pool in ipairs({ OFFENSIVE, SECOND, MOVEMENT }) do
  for _, name in ipairs(pool) do
    POOLED[#POOLED + 1] = name
  end
end

-- ----------------------------------------------------------------- state

-- The engine store is keyed by stable worm id (team * 16 + index), never by
-- entity address. It is virtual: WA's physical ammo is still alliance-shared
-- and is materialized from one worm's inventory at turn start.
local arsenal = wa.inventory.create({ id = "arsenal", slots = POOLED })
local dealt = {}

local function describe(list)
  if not list or #list == 0 then
    return "(nothing)"
  end
  return table.concat(list, ", ")
end

-- ----------------------------------------------------------------- rules

local function first(pool, n)
  local out = {}
  for i = 1, n do
    out[i] = pool[i]
  end
  return out
end

-- One from each pool, dealt to a worm on the first message it receives -- as
-- PX does on each worm's first M_FRAME. Dealing everyone at once on the very
-- first message would assume every worm already exists by then; this makes no
-- such assumption. Worms receive messages in WA's own entity order, which is
-- the same on every peer, so the draws still come out of WA's RNG in the same
-- sequence everywhere.
local function deal(worm)
  local cave = wa.world.cavern()
  arsenal:deal(worm, cave and first(OFFENSIVE, CAVE_OFFENSIVE) or OFFENSIVE, 1)
  arsenal:deal(worm, cave and first(SECOND, CAVE_SECOND) or SECOND, 1)
  arsenal:deal(worm, MOVEMENT, 1)
  dealt[worm.id] = true
  wa.log(string.format(
    "highlander: worm %d dealt %s (%s map)",
    worm.id, describe(arsenal:list(worm)), cave and "cavern" or "open"
  ))
end

local function start_turn(worm)
  arsenal:apply(worm, { clear = true, each = 1 })
  -- GiveWeapons: three Hot Air Balloons for the turn, whatever is left.
  worm:ammo("bungee", { set = 3 })
end

local function on_death(event)
  local victim = event.victim
  local active = event.active
  local mine = arsenal:list(victim)

  if active and active.id == victim.id then
    -- Died on its own turn: nothing to hand on, just take its weapons away.
    arsenal:clear(victim)
    arsenal:apply(victim, { clear = true, each = 1 })
    wa.log(string.format("highlander: worm %d died on its own turn", victim.id))
    return
  end

  -- Otherwise the worm whose turn it is gets everything -- whoever or
  -- whatever did the killing, friend or foe, exactly as in PX.
  if not active or active.hp <= 0 then
    return
  end
  arsenal:transfer(victim, active, { weapons = "all", mode = "move" })
  -- Usable at once, this turn, not from the stealer's next turn.
  arsenal:apply(active, { weapons = mine, each = 1 })
  wa.log(string.format(
    "highlander: worm %d took %s from worm %d",
    active.id, describe(mine), victim.id
  ))
end

wa.on.worm_message(function(worm, msg)
  if not dealt[worm.id] then
    deal(worm)
  end
end)

wa.on.turn_start(function(event)
  start_turn(event.worm)
end)

wa.on.death(on_death)
