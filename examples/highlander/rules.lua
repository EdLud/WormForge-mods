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
--     Changer to 1 each turn; so does start_turn.
--
-- Lockstep: dealing, turn_start and death are all dispatched from WA's own
-- simulation messages, and every random choice is wa.random(). Two peers, or
-- a peer and a replay, deal the same hands and make the same grants. Nothing
-- here reads local input or the clock.

-- ---------------------------------------------------------------- weapons

-- PX's sprite builder, for the weapons below whose hold PX draws at run
-- time: the worm posture with no weapon in it, and its hands. The engine
-- draws the weapon and optional hand from the hold claim below.
local PX_POSTURE = {
  weaponlnk = "sprites/px_hold/aim", weaponlnku = "sprites/px_hold/aimu",
  weaponlnkd = "sprites/px_hold/aimd",
  wthrow = "sprites/px_hold/draw", wthrowu = "sprites/px_hold/drawu",
  wthrowd = "sprites/px_hold/drawd",
}
local PX_HANDS = {
  "sprites/px_hold/hand_rad_lower", "sprites/px_hold/hand_rad", "sprites/px_hold/hand_rad_upper",
}
local PX_HOLDS = {
  prod = {
    keep_while_firing = true,
    sheet = "sprites/javelin/hold", draw_hand = false,
    hand_radius = 0, hand_rotation = 0, hand_radial_rotation = 0,
    weap_radial_rotation = 0, weap_rotation = 1, weap_radius = -11.8,
    animate = true, anim_speed = 1.25, frames = 12,
  },
  earthquake = { -- Electric Grenade (electric_grenade_anim)
    thrown = true,
    sheet = "sprites/px_hold/electric_grenade.png", hand_type = 1,
    hand_radius = 15, hand_scale = 0.8,
    weap_rotation = 0.5, weap_radius = 9,
  },
  grenade = { -- Sticky Bomb (sb_script)
    -- Thrown: once fired it has left the worm's hands, and WA puts nothing
    -- away (as for its own grenades), so neither does the rule.
    thrown = true,
    sheet = "sprites/px_hold/sticky_bomb", hand_type = 1, hand_radius = 24,
    hand_rotation = 1.0, hand_radial_rotation = 1.05, hand_scale = 0.8,
    weap_rotation = 0.5, weap_radial_rotation = 0.9, weap_radius = 10,
  },
  super_banana = { -- Chilli Bomb (chilli_bomb_anim)
    thrown = true,
    sheet = "sprites/px_hold/chilli_bomb", hand_type = 1, hand_radius = 13,
    hand_scale = 0.8, weap_rotation = 0.5, weap_radius = 9,
  },
  homing_missile = { -- Igniter (igniter_anim)
    -- Up through the shot too: it has no firing poses of its own, so WA
    -- fires it in the aim posture, empty-handed without the hold. Not PX's.
    keep_while_firing = true,
    sheet = "sprites/px_hold/igniter", hand_type = 2, hand_radius = -6.0,
    hand_rotation = 1.0, hand_radial_rotation = 0.9, hand_scale = 0.8,
    weap_rotation = 1.0, weap_radial_rotation = 0.0, weap_radius = 0.0,
  },
  mine = { -- Nuke Rocket (nuke_rocket_anim): held at a fixed angle, not
    -- the aim's (dont_rotate_with_angle), and placed, so never put away.
    thrown = true,
    sheet = "sprites/px_hold/nuke_rocket", hand_type = 2, hand_radius = 13.0,
    hand_rotation = -0.6, hand_radial_rotation = -0.95, hand_scale = 1.0,
    weap_rotation = 0.45, weap_radial_rotation = 1.0, weap_radius = 8.5,
    static = { weap = -0.1, hand = 0.4 }, -- ang_if_static, hand_ang_if_static
  },
  handgun = { -- Sniper Rifle (sniper_rifle_script): its hand at scale 0
    -- Up through each shot, with its laser, over the snipefire poses (the
    -- worm lit by the muzzle), so it does not flicker between the three.
    -- Not PX's: PX hides it until the worm aims again.
    keep_while_firing = true,
    -- A muzzle flash on each shot. Not PX's: its rifle and snipefire poses
    -- have none. The sentry gun's flare, smaller, at the barrel's tip (30
    -- pixels out, on the barrel 2 to the side, as the laser leaves it).
    flash = { sheet = "sprites/sniper_rifle/flash", out = 30, side = 2, scale = 0.45, frames = 3 },
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

-- Each replace claim carries its own hold data. The engine draws it and
-- handles walking/aim/firing; no simulation actors are created for it.
for _, p in pairs(PX_HOLDS) do
  if p.draw_hand ~= false then p.hand = PX_HANDS[p.hand_type or 2] end
end

-- Filled in by the Double Bazooka's and Nuke Rocket's sections further down.
local double_bazooka_explode
local nuke_rocket_explode
local chilli_bomb_explode
-- Weapons' on_fire, filled in by their sections below (jump, laser); one
-- table, the file being at Lua's 200 locals for one chunk.
local fires = {}
local lightning_click
local electric_grenade_explode
local restore_lightning_inventory
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
  { weapon = "ming_vase" },                                    -- Priceless Ming Vase
}

-- PX weapons that need only PX's art: its icons, copied byte for byte so
-- replays share them, and its strips split into frame folders with
-- tools/px_split_strip.py. Where PX draws the worm's hold at run time with
-- its sprite builder (p_sprite_builder), so does the engine from PX_HOLDS.
local PX_ART = {
  { -- Super Tele: the PX record is a type-3 cursor weapon on teleport's slot.
    weapon = "teleport",
    wep = "weps/teleport.wep",
    panel_icon = "sprites/super_tele/icon.png",
    on_select = { cursor = true },
    on_click = function(ev) fires.super_tele_click(ev) end,
  },
  { -- Javelin: stock flight, direct thrust or a permanent terrain stamp.
    weapon = "prod", wep = "weps/prod.wep",
    panel_icon = "sprites/javelin/icon.png",
    sprite = "missile", worm_sprites = PX_POSTURE,
    sprites = { "sprites/javelin/hold", "sprites/javelin/flight", "sprites/javelin/stamp" },
    sounds = { "sounds/javelin_impact.wav" },
    params = { gpu_prefix = "sprites/javelin/" },
    on_explode = function(ev) fires.javelin(ev) end,
  },
  { -- Laser Gun: a 5 s beam in place of the uzi's bullet (its section below).
    weapon = "uzi",
    wep = "weps/uzi.wep",
    panel_icon = "sprites/laser_gun/ico_lasergun.png",
    worm_sprites = {
      weaponlnk = "sprites/laser_gun/aim", weaponlnku = "sprites/laser_gun/aimu",
      weaponlnkd = "sprites/laser_gun/aimd",
      wthrow = "sprites/laser_gun/draw", wthrowu = "sprites/laser_gun/drawu",
      wthrowd = "sprites/laser_gun/drawd",
    },
    sprites = { "sprites/laser_gun/laser_beam.png", "sprites/laser_gun/laser_glow.png" },
    sounds = {
      "sounds/laser_gun/laser_start.wav", "sounds/laser_gun/laser_loop.wav",
      "sounds/laser_gun/laser_end.wav",
    },
    params = { gpu_prefix = "sprites/laser_gun/" },
    on_fire = function(fire) fires.laser(fire) end,
  },
  { -- Electric Grenade: stock flight and explosion, then PX's chaining arc.
    -- PX's record leaves the flight sprite 0 and PX draws the grenade at run
    -- time (electric_grenade_anim, PX_WEAP_SPRITES below). A grenade-type
    -- slot picks the worm's throw sheet from its flight sprite, and 0 has
    -- none, so the worm vanished: here the stock grenade, hidden in flight,
    -- as for the Sticky Bomb. The arc's sheets come with the Lightning
    -- Strike's (its entry below), this prefix being the hold's.
    weapon = "earthquake",
    wep = "weps/earthquake.wep",
    panel_icon = "sprites/electric_grenade/icon.png",
    sprite = "grenade",
    worm_sprites = PX_POSTURE,
    sprites = { "sprites/px_hold/electric_grenade.png" },
    sounds = { "sounds/lightning/tazer_loop.wav" },
    params = { gpu_prefix = "sprites/px_hold/" },
    on_explode = function(ev) electric_grenade_explode(ev) end,
  },
  { -- Lightning Strike: the PX strike is an effect, not WA's napalm plane.
    weapon = "napalm_strike",
    wep = "weps/napalm_strike.wep",
    panel_icon = "sprites/lightning/icon.png",
    -- With the Electric Grenade's arc and zap sheets: both weapons' effects
    -- are GPU sheets under this prefix.
    sprites = {
      "sprites/lightning/beam.png", "sprites/lightning/glow.png", "sprites/lightning/cloud.png",
      "sprites/electric_grenade/explosion", "sprites/electric_grenade/tazed1",
      "sprites/electric_grenade/tazed2",
    },
    sounds = { "sounds/lightning/thunder.wav", "sounds/lightning/hit.wav" },
    params = { gpu_prefix = "sprites/" },
    -- Click-only dispatch keeps the strike's cursor and turn handling.
    on_select = { cursor = true },
    -- The engine ends WA's prefire after a click-only fire. (A closure:
    -- lightning_click is defined further down.)
    on_click = function(ev) lightning_click(ev) end,
  },
  { -- Double Bazooka: a second shell carries on from where the first
    -- explodes (its section below). Held as a plain bazooka: the pack's
    -- record has launcher 3 (wbaz) at +0x34 where the scheme's has 7, the
    -- homing missile's recoloured wbaz2 (Weapon__hold_sheet, 0x51C060).
    weapon = "bazooka",
    panel_icon = "sprites/double_bazooka/double_bazooka_ico.png",
    on_explode = function(ev) double_bazooka_explode(ev) end,
  },
  { -- Nuke Rocket: a rocket fuses on the ground, then a nuke climbs out of
    -- it (its section below). PX draws both upright (a type 5 WeapSprite,
    -- mirrored flying left), as WA draws a flight sprite.
    weapon = "mine",
    panel_icon = "sprites/nuke_rocket/nuke_rocket_ico.png",
    sprite = "sprites/nuke_rocket/nuke_rocket_bullet.png",
    on_explode = function(ev) nuke_rocket_explode(ev) end,
    -- The engine draws its PX sprite-builder hold from PX_HOLDS:
    -- the record's own sprite is PX-only, which left WA no sheet to draw
    -- the worm with.
    worm_sprites = PX_POSTURE,
    sprites = {
      "sprites/px_hold/nuke_rocket",
    },
    sounds = { "sounds/nuke_rocket_launch.wav" },
    params = { gpu_prefix = "sprites/px_hold/" },
  },
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
      "sprites/px_hold/igniter", "sprites/igniter/flight",
    },
    params = { gpu_prefix = "sprites/" },
  },
  { -- Chilli Bomb: five more Chillis burst out of it, which burst into fire
    -- (its section below). PX's record has sprite 0 and PX draws the chilli
    -- at run time, turned to its flight (PX_WEAP_SPRITES below). A thrown
    -- weapon's worm posture is picked by its sprite, so the record keeps the
    -- banana, and each missile's own copy is set to 0 in flight instead.
    weapon = "super_banana",
    panel_icon = "sprites/chilli_bomb/chilli_ico.png",
    sprite = "banana",
    on_explode = function(ev) chilli_bomb_explode(ev) end,
    worm_sprites = PX_POSTURE,
    sprites = { "sprites/px_hold/chilli_bomb" },
    params = { gpu_prefix = "sprites/px_hold/" },
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
    sprites = { "sprites/px_hold/sticky_bomb" },
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
    -- A pack WAV plays only once an entry registers it.
    sounds = {
      "sounds/balloon/inflate1.wav", "sounds/balloon/inflate2.wav", "sounds/balloon/inflate3.wav",
      "sounds/balloon/pop1.wav", "sounds/balloon/pop2.wav", "sounds/balloon/pop3.wav",
      "sounds/balloon/pop4.wav",
    },
    params = { gpu_prefix = "sprites/balloon/" },
  },
  { -- Hang-Glider: WA's parachute, flown as PX's glider (below).
    weapon = "parachute",
    panel_icon = "sprites/hang_glider/ico_glider.png",
    sprites = { "sprites/hang_glider/glider", "sprites/hang_glider/pack" },
    sounds = { "sounds/hang_glider/hangopen.wav", "sounds/hang_glider/hangclose.wav" },
    params = { gpu_prefix = "sprites/hang_glider/" },
  },
  { -- Swim Suit: on the laser sight's slot; worn, the worm swims (below).
    weapon = "laser_sight",
    panel_icon = "sprites/swim_suit/ico_swimsuit.png",
    sprites = { "sprites/swim_suit/swim", "sprites/swim_suit/float", "sprites/swim_suit/ring" },
    sounds = { "sounds/swim_suit/putting_on_ssuit.wav" },
    params = { gpu_prefix = "sprites/swim_suit/" },
  },
  { -- Jump: on the ninja rope's slot; the worm leaves with the shot (below).
    weapon = "ninja_rope",
    panel_icon = "sprites/jump/jumpic.png",
    worm_sprites = {
      weaponlnk = "sprites/jump/aim", weaponlnku = "sprites/jump/aimu",
      weaponlnkd = "sprites/jump/aimd",
    },
    on_fire = function(fire) fires.jump(fire) end,
  },
  { -- Wind Changer: on the surrender's slot; sets the wind (below).
    weapon = "surrender",
    panel_icon = "sprites/wind_changer/ico_windchanger.png",
    sounds = {
      "sounds/wind_changer/breeze.wav", "sounds/wind_changer/calm_wind.wav",
      "sounds/wind_changer/strong_wind.wav",
    },
  },
  { -- Gravity Control: on low gravity's slot; sets the gravity (below).
    weapon = "low_gravity",
    panel_icon = "sprites/gravity_control/gravity_control_ico.png",
    sounds = { "sounds/gravity_control/activate.wav", "sounds/gravity_control/error.wav" },
  },
  { -- Helicopter: WA's jet pack, flown by PX's script (below).
    weapon = "jet_pack",
    panel_icon = "sprites/helicopter/heli_ico.png",
    sprites = { "sprites/helicopter/flying", "sprites/helicopter/jumpin" },
    sounds = {
      "sounds/helicopter/helicopterloop.wav",
      "sounds/helicopter/1.wav", "sounds/helicopter/2.wav", "sounds/helicopter/3.wav",
      "sounds/helicopter/4.wav",
      "sounds/helicopter/oops1.wav", "sounds/helicopter/oops2.wav", "sounds/helicopter/huh.wav",
      "sounds/helicopter/poop.wav", "sounds/helicopter/idiot.wav",
    },
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
    sprites = {
      "sprites/px_hold/sniper_rifle", "sprites/sniper_rifle/laser", "sprites/sniper_rifle/flash",
    },
    sounds = { "sounds/sniper_firing.wav" },
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

-- WEP_PATCH begin
-- Display names + named patches from each former weps/<slot>.wep,
-- as copy_from + name + patch (web editor style). Generated by tools/embed_weps.py.
-- Each patch is every field the .wep's import changed, so the slot fires as
-- it did; a field with no name yet goes in by offset ([0x0D0] = 2).
local WEP_NAME = {
  air_strike = "Mortar Strike",
  aqua_sheep = "Ghost Sheep",
  banana_bomb = "Super Gravedigger",
  battle_axe = "Thumper Nade",
  bazooka = "Double Bazooka",
  blow_torch = "BlowTorch",
  bungee = "Hot Air Balloon",
  carpet_bomb = "Thumper Nade Strike",
  cluster_bomb = "Windy Cluster",
  crate_shower = "Crate Shower",
  crate_spy = "Crate Spy",
  damage_x2 = "Skunk",
  double_turn_time = "Mole Bomb",
  dynamite = "Dynamite",
  fast_walk = "Fast Walk",
  fire_punch = "Fire Jump",
  flame_thrower = "Flame Thrower",
  girder = "Baseball Bat",
  girder_pack = "3 Girder Pack",
  grenade = "Sticky Bomb",
  handgun = "Sniper Rifle",
  holy_grenade = "Hellish Hand-Grenade",
  homing_missile = "Igniter",
  homing_pigeon = "Blaster Worm",
  invisibility = "Teleport",
  jet_pack = "Helicopter",
  laser_sight = "Swim Suit",
  longbow = "Shadow-Bolt",
  low_gravity = "Gravity Control",
  mad_cow = "Cow Launcher",
  magic_bullet = "Cluster Bomb",
  mail_strike = "Pigeon Strike",
  mb_bomb = "Banana Express",
  mine = "Nuke Rocket",
  ming_vase = "Priceless Ming Vase",
  minigun = "Burst Rifle",
  mole_bomb = "Gravler",
  mole_squadron = "Gravler Strike",
  mortar = "S.M.A.R.T Bomb",
  ninja_rope = "Jump",
  old_woman = "Old Woman Launcher",
  parachute = "Hang-Glider",
  pneumatic_drill = "Super Drill",
  sheep = "Pogo Sheep",
  sheep_launcher = "Burning Sheep Launcher",
  shotgun = "Real Shotgun",
  skunk = "Remote Roller",
  super_banana = "Chilli Bomb",
  surrender = "Wind Changer",
}
local WEP_PATCH = {
  air_strike = {
    uses_turn = 0,
    plane_sprite = 86,
    k_count = 4,
    k_spacing = 30,
    collision_radius = 4331582,
    bias = 0,
    damage = 100,
    sprite = 52,
    flight_flags = 466,
    trail = 20,
    gravity_pct = 260,
    [0x094] = 10,
    friction_pct = 70,
    fuse = 10000,
    alt_sprite = 75,
    detonation = 1,
    cluster_count = 5,
    cluster_speed = 30,
    cluster_power = 30,
    cluster_angle = -1,
    cluster_spread = 40,
    c_collision_radius = 4331646,
    c_damage = 100,
    c_blast = 15,
    c_sprite_count = 1,
    c_impact = 2,
    c_flags = 260,
    c_trail = 15,
    c_gravity_pct = 160,
    c_wind_pct = 50,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse = 10000,
    c_missile_type = 2,
    c_render_size = 4194368,
    c_burn_sprite = 50,
    c_homing_strength = 50,
    c_homing_sprite = 113,
    [0x1A8] = 100,
  },
  aqua_sheep = {
    requires_aiming = 0,
    uses_turn = 0,
    retreat = 5000,
    m_blast = 90,
    wind_pct = 50,
    fuse_default = 8000,
    fuse = 8000,
    render_size = 137342,
    burn_sprite = 0,
  },
  banana_bomb = {
    requires_aiming = 0,
    uses_turn = 0,
    pellets = 3,
    collision_radius = 4339766,
    bias = 75,
    blast = 50,
    impact = 5,
    flight_flags = 0,
    trail = 100,
    gravity_pct = 145,
    friction_pct = 116,
    fuse_default = 0,
    alt_sprite = 126,
    missile_type = 0,
    render_size = 4325376,
    burn_sprite = 7,
    homing_strength = 99,
    homing_sprite = 126,
    homing_arm = 50,
    [0x0D0] = 1,
    cluster_speed = 37,
    cluster_power = 35,
    cluster_spread = 45,
    c_collision_radius = 4194304,
    c_bias = 50,
    c_blast = 18,
    c_impact = 5,
    c_flags = 0,
    c_gravity_pct = 0,
    c_wind_pct = 0,
    [0x144] = 20,
    c_friction_pct = 116,
    c_fuse = 0,
    [0x154] = 126,
    c_burn_sprite = 7,
    c_homing_strength = 99,
    c_homing_sprite = 126,
    c_homing_arm = 15,
    [0x194] = 5,
    power_pct = 50,
    weight2 = 0,
  },
  battle_axe = {
    requires_aiming = 0,
    uses_turn = 0,
    fire_type = 1,
    subtype_param = 2,
    fire_method = 3,
    pellets = 2,
    grenade_style = 1,
    collision_radius = 4194304,
    bias = 10,
    damage = 100,
    blast = 40,
    impact = 1,
    flight_flags = 251,
    trail = 40,
    gravity_pct = 150,
    wind_pct = 50,
    bounce_pct = 100,
    friction_pct = 120,
    fuse = 9000,
    missile_type = 2,
    render_size = 4373598,
    burn_sprite = 60,
    homing_strength = 50,
    homing_sprite = 30,
    homing_turn = 8,
    [0x0D0] = 2,
    detonation = 1,
    cluster_count = 6,
    cluster_speed = 40,
    cluster_power = 30,
    cluster_spread = 45,
    c_collision_radius = 4395070,
    c_damage = 100,
    c_blast = 30,
    c_sprite_count = 1,
    c_impact = 5,
    c_flags = 252,
    c_trail = 40,
    c_gravity_pct = 120,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse = 9000,
    c_missile_type = 2,
    c_render_size = 4200512,
    c_homing_strength = 100,
    c_homing_sprite = 113,
    [0x194] = 3,
    weight2 = 70,
  },
  bazooka = {
    requires_aiming = 0,
    uses_turn = 0,
    blast = 20,
    trail = 20,
    burn_sprite = 0,
  },
  blow_torch = {
    uses_turn = 0,
  },
  bungee = {
    retreat = -1,
    subtype_param = 12,
    fire_method = 100,
  },
  carpet_bomb = {
    uses_turn = 0,
    retreat = 3000,
    plane_sprite = 87,
    k_count = 3,
    k_spacing = 30,
    bias = 10,
    blast = 40,
    impact = 1,
    flight_flags = 251,
    trail = 35,
    gravity_pct = 150,
    [0x094] = 10,
    friction_pct = 120,
    render_size = 4439166,
    burn_sprite = 60,
    homing_strength = 50,
    homing_sprite = 30,
    homing_accel = 0,
    homing_kind = 0,
    homing_arm = 0,
    [0x0E4] = 2,
    detonation = 1,
    cluster_count = 6,
    cluster_speed = 40,
    cluster_power = 30,
    cluster_spread = 45,
    c_collision_radius = 137342,
    c_damage = 100,
    c_blast = 25,
    c_sprite_count = 1,
    c_impact = 5,
    c_flags = 252,
    c_trail = 40,
    c_gravity_pct = 120,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse = 9000,
    c_missile_type = 2,
    power_pct = 50,
  },
  cluster_bomb = {
    requires_aiming = 0,
    uses_turn = 0,
    grenade_style = 0,
    bounce_extra = 48,
    cluster_count = 8,
    cluster_speed = 35,
    cluster_power = 25,
    cluster_spread = 40,
    c_flags = 615,
    c_gravity_pct = 200,
    [0x140] = 50,
  },
  damage_x2 = {
    requires_aiming = 1,
    shots = 0,
    uses_turn = 1,
    creates_projectile = 1,
    fire_type = 2,
    subtype_param = 0,
    fire_method = 2,
    m_proximity = 2,
    m_fuse = 5,
    m_damage = 100,
    sprite = 173,
    impact = 6,
    flight_flags = 131,
    gravity_pct = 100,
    wind_pct = 50,
    bounce_pct = 100,
    friction_pct = 100,
    alt_sprite = 65578,
    missile_type = 3,
    render_size = 4331646,
    burn_sprite = 4331646,
    homing_strength = 100,
    homing_sprite = 4,
    homing_kind = 15,
    homing_arm = 120,
    homing_time = 43,
    [0x0D0] = -4,
    detonation = 1,
    cluster_count = 1,
    c_damage = 100,
    c_blast = 30,
    c_sprite_count = 1,
    c_sprite = 173,
    c_impact = 6,
    c_flags = 131,
    c_gravity_pct = 100,
    c_wind_pct = 50,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse_default = 5000,
    c_fuse = 10000,
    [0x154] = 65577,
    c_missile_type = 3,
    c_render_size = 4331646,
    c_homing_strength = 100,
    c_homing_sprite = 4,
    c_homing_kind = 15,
    c_homing_arm = 120,
    c_homing_time = 43,
    [0x194] = -4,
    [0x198] = 1,
    [0x19C] = 15,
    [0x1A0] = 174,
  },
  double_turn_time = {
    requires_aiming = 1,
    shots = 0,
    uses_turn = 1,
    creates_projectile = 1,
    fire_type = 2,
    subtype_param = 0,
    fire_method = 2,
    m_proximity = 2,
    m_fuse = 5,
    m_damage = 100,
    sprite = 166,
    impact = 6,
    flight_flags = 131,
    gravity_pct = 100,
    wind_pct = 50,
    bounce_pct = 100,
    friction_pct = 100,
    fuse_default = 5000,
    fuse = 5000,
    alt_sprite = 65575,
    space_control = 1,
    missile_type = 3,
    render_size = 4331646,
    burn_sprite = 4331646,
    homing_strength = 50,
    homing_sprite = 8,
    homing_kind = 15,
    homing_arm = 75,
    homing_time = 40,
    [0x0D0] = -4,
    detonation = 1,
    cluster_count = 1,
    c_collision_radius = 137340,
    c_damage = 110,
    c_blast = 40,
    c_sprite_count = 1,
    c_sprite = 152,
    c_impact = 6,
    c_flags = 80,
    c_trail = 50,
    c_gravity_pct = 50,
    c_wind_pct = 50,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse_default = 5000,
    c_fuse = 20000,
    c_space_control = 1,
    c_missile_type = 4,
    c_render_size = 50,
    c_burn_sprite = 50,
    c_homing_strength = 65574,
    c_homing_sprite = 158,
    c_homing_turn = 159,
    c_homing_accel = 160,
    c_homing_speed = 160,
  },
  dynamite = {
    requires_aiming = 0,
    uses_turn = 0,
    retreat = 0,
  },
  fire_punch = {
    requires_aiming = 0,
    uses_turn = 0,
    fire_method = 45,
    spread = 80,
    [0x1C0] = 7536640,
    [0x1C4] = 1874124,
    power_pct = 2090598400,
  },
  girder = {
    uses_turn = 0,
    creates_projectile = 1,
    subtype_param = 2,
    fire_method = 30,
    pellets = 125,
  },
  girder_pack = {
    shots = 3,
    uses_turn = 0,
  },
  grenade = {
    requires_aiming = 0,
    uses_turn = 0,
    collision_radius = 4394622,
    bias = 0,
    damage = 0,
    blast = 0,
    sprite = 0,
    fuse_default = 0,
    fuse = 2000000,
    glow_sprite = 39,
    missile_type = 0,
    burn_sprite = 152,
    homing_strength = 6,
    homing_kind = 2,
    homing_arm = 1,
    homing_time = 20000,
    detonation = 1,
    cluster_count = 1,
    c_collision_radius = 4194304,
    c_damage = 60,
    c_blast = 55,
    c_sprite_count = 1,
    c_impact = 1,
    c_flags = 80,
    c_trail = 50,
    c_gravity_pct = 50,
    c_wind_pct = 50,
    c_friction_pct = 100,
    c_fuse_default = 4000,
    c_fuse = 4000,
    [0x154] = 56,
    [0x158] = 1,
    c_missile_type = 4,
    c_homing_sprite = 467,
    c_homing_turn = 467,
    c_homing_accel = 467,
    c_homing_speed = 467,
    power_pct = 25,
  },
  handgun = {
    requires_aiming = 0,
    shots = 3,
    uses_turn = 0,
    h_shots = 1,
    h_spread = 1000,
    h_delay = 0,
    h_range = 4398206,
    [0x058] = 100,
    h_damage = 18,
    sprite = 50,
    h_kind = 7,
    weight2 = 20,
  },
  holy_grenade = {
    requires_aiming = 0,
    uses_turn = 0,
    damage = 70,
    blast = 80,
    flight_flags = 8,
    trail = 20,
    glow_sprite = 154,
    homing_sprite = 161,
    detonation = 2,
    cluster_count = 150,
    cluster_speed = 70,
    cluster_power = 1000,
    cluster_angle = 1,
  },
  homing_missile = {
    uses_turn = 0,
    subtype_param = 3,
    bias = 0,
    impact = 2,
    gravity_pct = 0,
    fuse = 9000,
    missile_type = 2,
    render_size = 4194304,
    burn_sprite = 1,
    homing_strength = 0,
    homing_sprite = 0,
    homing_turn = 8,
    homing_accel = 0,
    homing_speed = 0,
    homing_kind = 0,
    homing_arm = 0,
    homing_time = 0,
    detonation = 2,
    cluster_count = 150,
    cluster_speed = 150,
    cluster_power = 1000,
    cluster_angle = 1,
  },
  homing_pigeon = {
    uses_turn = 0,
    subtype_param = 3,
    spread = 0,
    bias = 0,
    blast = 50,
    impact = 2,
    gravity_pct = 0,
    wind_pct = 0,
    fuse = 9000,
    alt_sprite = 157,
    missile_type = 0,
    render_size = 4194304,
    burn_sprite = 1,
    homing_strength = 0,
    homing_sprite = 0,
    homing_turn = 8,
    homing_accel = 0,
    homing_speed = 0,
    homing_kind = 0,
    homing_arm = 0,
    homing_time = 0,
    detonation = 1,
    [0x0F4] = 0,
    cluster_count = 1,
    cluster_speed = 80,
    cluster_power = 80,
    cluster_spread = 100,
    c_sprite_count = 1,
    c_impact = 1,
    c_flags = 249,
    c_trail = 28,
    c_gravity_pct = 125,
    c_bounce_pct = 99,
    [0x144] = 5,
    c_friction_pct = 100,
    c_fuse = 7000,
    [0x154] = 162,
    c_missile_type = 2,
    c_render_size = 4398206,
    c_burn_sprite = 60,
    c_homing_strength = 60,
    c_homing_sprite = 56,
    [0x194] = 6,
  },
  invisibility = {
    requires_aiming = 0,
    uses_turn = 1,
    subtype_param = 10,
    pellets = 0,
  },
  jet_pack = {
    retreat = -1,
    fire_method = 255,
    pellets = 8,
  },
  laser_sight = {
    requires_aiming = 0,
  },
  longbow = {
    requires_aiming = 0,
    uses_turn = 0,
    subtype_param = 2,
    fire_method = 3,
    pellets = 3,
    collision_radius = 4332604,
    bias = 8,
    damage = 250,
    blast = 28,
    impact = 2,
    flight_flags = 453,
    trail = 40,
    gravity_pct = 180,
    wind_pct = 50,
    bounce_pct = 100,
    friction_pct = 110,
    fuse = 10000,
    alt_sprite = 122,
    missile_type = 2,
    render_size = 1077936192,
    burn_sprite = 80,
    homing_strength = 80,
    homing_sprite = 83,
    [0x0D0] = 10,
  },
  low_gravity = {
    retreat = -1,
    pellets = 8,
  },
  mad_cow = {
    requires_aiming = 0,
    uses_turn = 0,
    fire_type = 1,
    subtype_param = 3,
    fire_method = 3,
    spread = 50,
  },
  magic_bullet = {
    requires_aiming = 1,
    subtype_param = 2,
    spread = 0,
    grenade_style = 1,
    collision_radius = 0,
    damage = 0,
    blast = 20,
    sprite = 53,
    flight_flags = 131,
    fuse_default = 5000,
    fuse = 0,
    alt_sprite = 0,
    missile_type = 2,
    render_size = 4331614,
    burn_sprite = 0,
    homing_strength = 100,
    homing_sprite = 113,
    homing_turn = 8,
    homing_accel = 0,
    homing_speed = 0,
    homing_kind = 0,
    homing_arm = 0,
    homing_time = 0,
    detonation = 1,
    cluster_count = 5,
    cluster_speed = 30,
    cluster_power = 30,
    cluster_spread = 45,
    c_collision_radius = 137342,
    c_damage = 100,
    c_blast = 20,
    c_sprite_count = 1,
    c_sprite = 54,
    c_impact = 1,
    c_flags = 131,
    c_trail = 20,
    c_gravity_pct = 100,
    c_wind_pct = 50,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse = 9000,
    c_missile_type = 2,
    c_render_size = 4331614,
    c_homing_strength = 100,
    c_homing_sprite = 113,
    c_homing_turn = 8,
    power_pct = 25,
    weight2 = 70,
  },
  mail_strike = {
    uses_turn = 0,
    retreat = 3000,
    subtype_param = 0,
    plane_sprite = 86,
    k_count = 3,
    k_spacing = 45,
    h_delay = 1200,
    collision_radius = 4331646,
    bias = 25,
    blast = 55,
    sprite = 175,
    impact = 3,
    flight_flags = 0,
    trail = 50,
    bounce_pct = 95,
    bounce_extra = 0,
    [0x094] = 180,
    friction_pct = 25,
    fuse = 12000,
    alt_sprite = 65587,
    missile_type = 1,
    burn_sprite = 175,
    homing_strength = 1,
    homing_sprite = 134,
    homing_turn = 25,
    homing_accel = 40,
    homing_speed = 50,
    homing_kind = 1,
    homing_arm = 2400,
    homing_time = 1000,
    detonation = 1,
    cluster_count = 18,
    cluster_speed = 15,
    cluster_power = 30,
    cluster_spread = 20,
    c_collision_radius = 137282,
    c_sprite_count = 1,
    c_sprite = 134,
    c_impact = 1,
    c_wind_pct = 50,
    c_bounce_pct = 99,
    [0x158] = 60,
    c_friction_pct = 45,
    c_fuse = 10000,
    c_missile_type = 2,
    c_render_size = 137282,
    c_burn_sprite = 20,
    c_homing_strength = 20,
    c_homing_turn = 8,
    [0x1A8] = 1,
    power_pct = 50,
  },
  mb_bomb = {
    requires_aiming = 0,
    uses_turn = 0,
    retreat = 3000,
    subtype_param = 0,
    k_spacing = 30,
    h_delay = 150,
    h_flag = 52,
    collision_radius = 0,
    damage = 80,
    blast = 70,
    sprite = 51,
    impact = 1,
    flight_flags = 131,
    trail = 0,
    gravity_pct = 100,
    wind_pct = 50,
    bounce_pct = 100,
    bounce_extra = 0,
    [0x094] = 0,
    fuse_default = 3000,
    fuse = 10000,
    space_control = 1,
    render_size = 4398718,
    burn_sprite = 60,
    homing_strength = 100,
    homing_sprite = 111,
    detonation = 1,
    cluster_count = 5,
    cluster_speed = 45,
    cluster_power = 30,
    cluster_spread = 25,
    c_collision_radius = 4331646,
    c_damage = 80,
    c_blast = 60,
    c_sprite_count = 1,
    c_sprite = 51,
    c_impact = 1,
    c_flags = 131,
    c_gravity_pct = 100,
    c_wind_pct = 50,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse = 9000,
    c_missile_type = 2,
    c_render_size = 204414,
    c_burn_sprite = 60,
    c_homing_strength = 100,
    c_homing_sprite = 111,
    c_homing_turn = 8,
    power_pct = 50,
  },
  mine = {
    requires_aiming = 0,
    uses_turn = 0,
    fire_method = 2,
    m_proximity = 2,
    m_fuse = 5,
    m_mask = 1,
    m_trigger = 0,
    m_damage = 70,
    m_blast = 0,
    impact = 2,
    flight_flags = 131,
    gravity_pct = 100,
    wind_pct = 50,
    bounce_pct = 100,
    friction_pct = 100,
    fuse = 3000,
    alt_sprite = 65602,
    missile_type = 2,
    render_size = 4331614,
    burn_sprite = 30,
    homing_sprite = 113,
    homing_turn = 8,
    cluster_count = 5,
    cluster_speed = 33,
    cluster_power = 33,
    cluster_spread = 30,
    c_collision_radius = 4332670,
    c_damage = 25,
    c_blast = 20,
    c_sprite_count = 1,
    c_sprite = 54,
    c_impact = 1,
    c_flags = 131,
    c_gravity_pct = 100,
    c_wind_pct = 50,
    c_bounce_pct = 100,
    c_friction_pct = 100,
    c_fuse = 7770,
    c_missile_type = 2,
    c_burn_sprite = 1,
    c_homing_turn = 8,
    weight2 = 100,
  },
  ming_vase = {
    requires_aiming = 0,
    uses_turn = 0,
  },
  minigun = {
    requires_aiming = 0,
    uses_turn = 0,
    h_shots = 10,
    h_spread = 63,
    h_delay = 6,
    h_flag = 2,
    bias = 6,
    h_radius = 15,
    h_damage = 7,
  },
  mole_bomb = {
    requires_aiming = 0,
    uses_turn = 0,
    retreat = 3000,
    fire_type = 1,
    subtype_param = 3,
    fire_method = 3,
    spread = 0,
    collision_radius = 137340,
    damage = 110,
    blast = 40,
    sprite = 245,
    impact = 2,
    flight_flags = 0,
    gravity_pct = 0,
    friction_pct = 85,
    fuse = 20000,
    alt_sprite = 0,
    space_control = 0,
    missile_type = 4,
    render_size = 50,
    burn_sprite = 50,
    homing_strength = 65574,
    homing_sprite = 245,
    homing_turn = 246,
    homing_accel = 247,
    homing_speed = 248,
    detonation = 0,
    weight2 = 100,
  },
  mole_squadron = {
    uses_turn = 0,
    k_count = 4,
    k_spacing = 15,
    h_delay = 110,
    collision_radius = 135228,
    blast = 37,
    sprite = 245,
    impact = 2,
    flight_flags = 0,
    trail = 0,
    gravity_pct = 0,
    [0x094] = 12,
    friction_pct = 90,
    fuse_default = 3000,
    fuse = 5000,
    homing_sprite = 245,
    homing_turn = 246,
    homing_accel = 247,
    homing_speed = 248,
  },
  mortar = {
    requires_aiming = 0,
    uses_turn = 0,
    subtype_param = 3,
    spread = 0,
    collision_radius = 170110,
    flight_flags = 250,
    trail = 40,
    gravity_pct = 120,
    friction_pct = 125,
    cluster_count = 7,
    cluster_speed = 50,
    cluster_angle = 0,
    cluster_spread = 45,
    c_damage = 115,
    c_blast = 25,
    c_impact = 1,
    c_flags = 0,
    c_trail = 2,
    c_gravity_pct = 600,
    c_wind_pct = 0,
    [0x154] = 46,
    c_missile_type = 1,
    c_homing_strength = 1,
    c_homing_sprite = 608,
    c_homing_turn = 6,
    c_homing_accel = 500,
    c_homing_kind = 1,
    c_homing_arm = 1100,
    c_homing_time = 1200,
  },
  ninja_rope = {
    requires_aiming = 0,
    retreat = 3000,
    creates_projectile = 1,
    fire_type = 1,
    subtype_param = 2,
    fire_method = 3,
    pellets = 2,
    grenade_style = 1,
    bias = 10,
    damage = 100,
    blast = 50,
    sprite = 50,
    impact = 1,
    flight_flags = 131,
    gravity_pct = 100,
    wind_pct = 50,
    bounce_pct = 100,
    friction_pct = 100,
    fuse_default = 5000,
    missile_type = 2,
    render_size = 4331614,
    homing_strength = 100,
    homing_sprite = 113,
    homing_turn = 8,
    weight2 = 70,
  },
  old_woman = {
    requires_aiming = 0,
    uses_turn = 0,
    fire_type = 1,
    subtype_param = 3,
    fire_method = 3,
    spread = 50,
    flight_flags = 135,
    trail = 50,
    fuse = 6000,
    homing_time = 65,
    cluster_count = 20,
    cluster_speed = 30,
    cluster_power = 2000,
  },
  pneumatic_drill = {
    requires_aiming = 0,
    uses_turn = 0,
    grenade_style = 2000,
  },
  sheep = {
    requires_aiming = 0,
    uses_turn = 0,
    m_fuse = 6,
    m_blast = 65,
    impact = 2,
    [0x080] = 8,
    friction_pct = 70,
    fuse_default = 0,
    alt_sprite = 50,
    missile_type = 2,
    render_size = 1078074494,
    burn_sprite = 98,
    homing_sprite = 111,
    [0x0D0] = 50,
    detonation = 1,
    cluster_count = 48,
    cluster_speed = 1,
    cluster_power = 30,
    cluster_spread = 45,
    c_sprite_count = 1,
    c_flags = 249,
    c_trail = 1,
    c_gravity_pct = 20,
    c_wind_pct = 50,
    c_bounce_pct = 65,
    [0x144] = 650,
    c_friction_pct = 75,
    c_fuse = 2000,
    c_missile_type = 2,
    c_render_size = 2,
    c_burn_sprite = 10,
    c_homing_strength = 10,
    [0x194] = 10,
  },
  sheep_launcher = {
    requires_aiming = 0,
    uses_turn = 0,
    subtype_param = 3,
    spread = 0,
    collision_radius = 0,
    damage = 100,
    blast = 50,
    sprite = 64,
    impact = 1,
    trail = 20,
    gravity_pct = 50,
    wind_pct = 0,
    fuse = 9000,
    space_control = 0,
    render_size = 4194430,
    burn_sprite = 50,
    homing_strength = 30,
    homing_accel = 50,
    homing_kind = 100,
    homing_arm = 50,
    [0x0D0] = 2,
    detonation = 2,
    cluster_count = 40,
    cluster_speed = 100,
    cluster_power = 4000,
  },
  shotgun = {
    requires_aiming = 0,
    uses_turn = 0,
    h_delay = 10,
    bias = 10,
    h_range = 4365438,
    [0x058] = 150,
    sprite = 75,
  },
  skunk = {
    requires_aiming = 0,
    uses_turn = 0,
    m_fuse = 15,
    m_mask = 1,
    bias = 10,
    m_damage = 110,
    m_blast = 43,
    flight_flags = 80,
    trail = 10,
    gravity_pct = 30,
    bounce_pct = 101,
    friction_pct = 90,
    fuse_default = 0,
    fuse = 15000,
    alt_sprite = 88,
    render_size = 1078139998,
    burn_sprite = 0,
    homing_strength = 110,
    homing_sprite = 20,
    homing_turn = 25,
    homing_accel = 50,
    homing_speed = 88,
    homing_kind = 0,
    homing_arm = 0,
    homing_time = 88,
    [0x0D0] = -5,
    detonation = 0,
    cluster_count = 0,
    c_damage = 0,
    c_blast = 0,
    c_sprite_count = 0,
    c_sprite = 0,
    c_impact = 0,
    c_flags = 0,
    c_gravity_pct = 0,
    c_wind_pct = 0,
    c_bounce_pct = 0,
    c_friction_pct = 0,
    c_fuse_default = 0,
    c_fuse = 0,
    [0x154] = 0,
    c_space_control = 0,
    c_missile_type = 0,
    c_render_size = 0,
    c_burn_sprite = 0,
    c_homing_strength = 0,
    c_homing_sprite = 0,
    c_homing_kind = 0,
    c_homing_arm = 0,
    c_homing_time = 0,
    [0x194] = 0,
    [0x198] = 0,
    [0x19C] = 0,
    [0x1A0] = 0,
    weight2 = 70,
  },
  super_banana = {
    requires_aiming = 0,
    uses_turn = 0,
    retreat = 3000,
    grenade_style = 1,
    damage = 75,
    blast = 50,
    fuse_default = 5000,
    fuse = 0,
    space_control = 0,
    render_size = 4331614,
    detonation = 0,
    cluster_count = 20,
    cluster_speed = 30,
    cluster_power = 1500,
    cluster_spread = 45,
    c_collision_radius = 137342,
    c_bias = 1,
    c_blast = 20,
    c_sprite = 0,
    c_trail = 20,
    c_fuse = 2000,
    c_space_control = 0,
    c_render_size = 4331614,
    c_burn_sprite = 0,
    c_homing_sprite = 113,
    power_pct = 25,
    weight2 = 70,
  },
  surrender = {
    requires_aiming = 0,
    uses_turn = 0,
    retreat = 0,
    subtype_param = 19,
    pellets = 8,
  },
}
-- WEP_PATCH end

for _, list in ipairs({ PORTED, PX_ART }) do
  for _, w in ipairs(list) do
    -- copy_from + name + named patch (stock base); was weps/<slot>.wep
    local spec = w.wep and { wep = w.wep } or { copy_from = w.weapon, name = WEP_NAME[w.weapon] }
    if not w.wep and WEP_PATCH[w.weapon] then
      spec.patch = WEP_PATCH[w.weapon]
    end
    for key, value in pairs(w) do
      spec[key] = value
    end
    spec.hold = PX_HOLDS[w.weapon]
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

-- PX's missile sprite animations share these two helpers. Holds are drawn
-- by the engine from each replace claim's hold table above.
local HOLD_DEPTH = 0x10000
local function next_phase(phase, anim_speed)
  if phase > 0.99 then return 0 end
  return phase + anim_speed * 30 / 1000
end
local function frame_of(phase, frames)
  return math.min(math.floor(phase * frames), frames - 1)
end

-- The Sniper Rifle's sight remains a draw callback. Keep only its last aim
-- through its firing poses; the rifle and flash themselves are engine draws.
local held = {}
wa.on.worm_message(function(worm, msg)
  local h = held[worm.id]
  if msg == wa.msg.FIRE_WEAPON and h then h.firing = true end
  if msg ~= wa.msg.FRAME_FINISH then return end
  if worm.weapon == "handgun" and worm.aiming then
    held[worm.id] = { slot = "handgun", aim = worm.aim }
  elseif not (h and h.firing and worm.weapon == "handgun"
      and (worm.state == "firing" or worm.state == "fired")) then
    held[worm.id] = nil
  end
end)

-- ------------------------------------------ the Sniper Rifle's laser sight
-- Shared with later sections; the rest of this section is local to it.
local STOPPERS
do
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
STOPPERS = { { wa.worms, 6 }, { wa.mines, 4 }, { wa.crates, 10 }, { wa.oil, 9 } }

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
      local aim = h and h.slot == "handgun" and h.aim
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
end

-- ------------------------------------ PX's missile sprites, at run time
-- Shared with later sections; the rest of this section is local to it.
local flying, current_worm
do
--
-- For some weapons PX draws the missile itself (p_sprite_builder,
-- WeapSprite) and leaves WA's sprite 0: a sprite that follows the missile,
-- turned to its flight, mirrored when it flies left, and, if `animate`,
-- stepped through its sheet as a hold is. Here it is a GPU actor per
-- missile, placed from wa.on.missile_frame after WA has moved the missile.
-- It reads m.weapon (the missile's slot); on an engine without it nothing
-- matches and nothing is drawn. With `hide`, WA draws nothing for the
-- missile (m.sprite = 0), as PX's sprite 0 does; its record keeps its
-- sprite, which a thrown weapon's worm posture is picked by.
--
-- How it turns follows the record's animation type (the entry's +0x64,
-- PX's launchdata.anim.type): 2, WAT_TrackMovement, faces its flight
-- (WeapSprite type 2, as a bazooka shell); 1, WAT_Rotation, spins with its
-- speed (type 3, as a grenade), which `spin` asks for.

-- Slot -> the weapon's WeapSpriteParams, as its PX script states them.
local PX_WEAP_SPRITES = {
  prod = {
    sheet = "sprites/javelin/flight", hide = true,
    animate = true, anim_speed = 1.90, frames = 12,
  },
  longbow = { -- Shadow-Bolt
    sheet = "sprites/shadow_bolt/bolt", animate = true, anim_speed = 1.30, frames = 6,
  },
  super_banana = { -- Chilli Bomb (chilli_bomb_anim) and the five it bursts into
    sheet = "sprites/px_hold/chilli_bomb", frames = 1,
    spin = true, -- its record's WAT_Rotation
    -- WA's own sprite 0, as PX's record has it: nothing under the chilli.
    hide = true,
  },
  homing_missile = { -- Igniter (igniter_anim: igniter_bullet, 16 frames)
    sheet = "sprites/igniter/flight", animate = true, anim_speed = 1.0, frames = 16,
  },
  earthquake = { -- Electric Grenade (electric_grenade_anim: electric_grenade_bullet)
    sheet = "sprites/px_hold/electric_grenade.png", frames = 1,
    spin = true, -- its record's WAT_Rotation
    -- PX's record has sprite 0; the pack's stock grenade is only for the
    -- worm's throw sheet.
    hide = true,
  },
}

flying = {} -- missile id -> { actor, phase, seen }

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
function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then
      return w
    end
  end
end

wa.on.missile_frame(function(m)
  local p = PX_WEAP_SPRITES[m.weapon]
  if p and p.hide and m.phase == "pre" then
    m.sprite = 0
  end
  p = m.phase == "post" and p
  if not p then
    return
  end
  local f = flying[m.id]
  if not f then
    local owner = current_worm()
    if not owner then
      return
    end
    f = { phase = 0, rot = 0 }
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
  local rot
  if p.spin then
    -- WeapSprite type 3: 0.5 * (vx * 0.15 + |vy| * 0.01, towards vx) a
    -- frame, in pixels a frame and radians.
    local vx, vy = m.vx / 0x10000, m.vy / 0x10000
    local sign = vx > 0 and 1 or vx < 0 and -1 or 0
    f.rot = f.rot + 0.5 * (vx * 0.15 + math.abs(vy * 0.01) * sign)
    rot = f.rot
  else
    -- WeapSprite::CalculateAngle, rotation 0.
    rot = -math.atan(m.vx, m.vy) - math.pi
  end
  a:gfx({ angle = math.deg(rot) % 360, depth = HOLD_DEPTH })
end)
end

-- ---------------------------------------------------------- Double Bazooka
do
--
-- PX's double_bazooka_script. A Double Bazooka shell does not end at the
-- first thing it hits: WA's explosion goes off, a 50-pixel hole is cut
-- (GG->land->MakeHole(50), WA's landscape "apply explosion", as
-- wa.land.dig), and a second shell carries on from there at the first one's
-- speed, a real WA missile of the same slot (new CMissile with the weapon's
-- launch data), so WA flies it with wind and its smoke trail. PX changes
-- three things for it: damage 40, sprite 54 and a 5 s fuse. The port takes
-- the damage and fuse; 54 is a cluster bit (clustlet) in WA 3.8.1, so the
-- second shell keeps the record's bazooka shell (48, missile), as the first
-- does. Its own explosion ends it.
--
-- Not ported: PX's particle trail on top of WA's (pxparticles), and a plain
-- 50/35 blast PX makes when a second shell explodes before its first frame.

local DB_SECOND = { damage = 40, fuse = 5000 }
local DB_HOLE = 50

local db_speed = {}   -- missile id -> { vx, vy } at its last frame
local db_second = {}  -- missile id -> true: a second shell, which ends it
local db_pending = {} -- second shells to launch once the blast is over
local db_shooter      -- the worm that fired it (PX's ClWT / ClWN)

wa.on.missile_frame(function(m)
  if m.weapon == "bazooka" and m.phase == "post" then
    db_speed[m.id] = { m.vx, m.vy }
  end
end)

double_bazooka_explode = function(ev)
  local id = ev.missile
  if not id then
    return
  end
  local speed = db_speed[id]
  db_speed[id] = nil
  if db_second[id] then
    db_second[id] = nil
    return
  end
  if not speed then
    return
  end
  wa.land.dig({ x = ev.x, y = ev.y, radius = DB_HOLE })
  -- Launched after the blast, as PX's comes after super: WA's explosion
  -- would otherwise push it.
  db_pending[#db_pending + 1] = { x = ev.x, y = ev.y, vx = speed[1], vy = speed[2] }
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FIRE_WEAPON and worm.weapon == "bazooka" then
    db_shooter = worm
  elseif msg == wa.msg.FRAME_FINISH and #db_pending > 0 then
    -- The first worm's frame after the blast; every worm gets one.
    local owner = db_shooter or worm
    for _, p in ipairs(db_pending) do
      local id = wa.weapons.launch({
        weapon = "bazooka", owner = owner, x = p.x, y = p.y, vx = p.vx, vy = p.vy,
        damage = DB_SECOND.damage, fuse = DB_SECOND.fuse,
      })
      db_second[id] = true
    end
    db_pending = {}
  end
end)
end

-- ------------------------------------------------------------- Chilli Bomb
do
--
-- PX's pyro_grenades_script (PyroMan), on WA's super banana. When a Chilli
-- Bomb explodes, five more Chillis burst out of it, straight up with a
-- random spread (PX's ShotClustlets): real WA missiles of the same slot,
-- each with damage 30, an 8 s fuse, no countdown, the fire key setting it
-- off, and a burst of fire where it ends. The five do not burst again: a
-- missile PX's script makes has no weapon of its own (weap), so its
-- ExplodeAt skips the Chilli's branch.
--
-- Not ported: PX's particle trail and the sparks while aiming
-- (pxparticles), and the smoke trail's power of 20 on the five. PX also
-- writes the five's changes into the weapon's own launch data, so every
-- later Chilli Bomb flies with them; the port changes the five only.

local CHILLI_CHILD = { count = 5, damage = 30, fuse = 8000 }

local chilli_child = {}   -- missile id -> true: one of the five, which ends it
local chilli_pending = {} -- where the five burst out, once the blast is over
local chilli_shooter      -- the worm that threw it (PX's ClWT / ClWN)

chilli_bomb_explode = function(ev)
  local id = ev.missile
  if not id then
    return
  end
  if chilli_child[id] then
    chilli_child[id] = nil
    return
  end
  chilli_pending[#chilli_pending + 1] = { x = ev.x, y = ev.y }
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FIRE_WEAPON and worm.weapon == "super_banana" then
    chilli_shooter = worm
  elseif msg == wa.msg.FRAME_FINISH and #chilli_pending > 0 then
    -- After the blast, as the Double Bazooka's second shell.
    local P = 0x10000
    local owner = chilli_shooter or worm
    for _, p in ipairs(chilli_pending) do
      for _ = 1, CHILLI_CHILD.count do
        -- RandomFloat(3, -3), then RandomFloat(-7, -10).
        local vx = wa.random(-3 * P, 3 * P)
        local vy = wa.random(-10 * P, -7 * P)
        local id = wa.weapons.launch({
          weapon = "super_banana", owner = owner, x = p.x, y = p.y, vx = vx, vy = vy,
          damage = CHILLI_CHILD.damage, fuse = CHILLI_CHILD.fuse, countdown = 0,
          explode_on_space = true, explode_into = "fire",
          sprite = 0, -- PX leaves them WA's sprite 0; the chilli is drawn instead
        })
        chilli_child[id] = true
      end
    end
    chilli_pending = {}
  end
end)
end

-- ------------------------------------------------------------ Nuke Rocket
do
--
-- PX's nuke_rocket_script, on the mine slot. The scheme's record is a
-- placed weapon that WA fires as a missile (fire type 2, method 2:
-- CreateWeaponProjectile), and it already has every value PX's FireFinal
-- gives its first rocket (a 3 s fuse, damage 0, bias 50, push 70, sound
-- 66). So WA's own shot is PX's first rocket: it fuses on the ground,
-- hissing (sound 66 every 10 frames). When it explodes, a nuke climbs out
-- of it: a real WA missile of the same slot (wa.weapons.launch, as PX's
-- MakeNuke creates a CMissile), silent, with a 1.6 s fuse, bursting into
-- the record's clustlets. For 53 frames it climbs, randomly and jittering
-- sideways, and carries worms and missiles within 17 pixels along; then
-- it brakes. Its explosion adds PX's two 40/40 blasts and sounds 85, 70.
--
-- Not ported: PX's particle trails, and carrying mines, crates, oil drums
-- and bowling balls (their speed is not writable from Lua).

local P16 = 0x10000
local NR_HISS = 66    -- the fusing rocket's hiss, every 10 frames
local NR_CLIMB = 53   -- frames the nuke climbs (PX: "1.1-1.2 second")
local NR_CARRY = 17   -- pixels: what the climbing nuke carries along
local NUKE = { fuse = 1600, sound = 0, explode_into = "clustlets" }
local NUKE_BLAST = { damage = 40, id = 40 } -- PX's DoExplosion(x, y, 40, 40), twice

local nr_first = {}    -- missile id -> frames: a first rocket, fusing
local nr_speed = {}    -- missile id -> { vx, vy } at its last frame
local nr_nuke = {}     -- missile id -> frames flown: a nuke
local nr_climbing = {} -- nuke id -> { x, y, vx, vy }, while it climbs
local nr_pending = {}  -- nukes to launch once the rocket's blast is over
local nr_shooter       -- the worm that fired (PX's ClWT / ClWN)
local nr_expect        -- fired: the next mine-slot missile is the rocket

local function near(ax, ay, bx, by)
  local r = NR_CARRY * P16
  return math.abs(ax - bx) < r and math.abs(ay - by) < r
end

wa.on.missile_frame(function(m)
  local t = nr_nuke[m.id]
  if t ~= nil then
    -- Before WA moves it, as PX's M_FRAME runs before super.
    if m.phase ~= "pre" then
      return
    end
    if t < NR_CLIMB then
      m.vy = m.vy - wa.random(19661, 52429) -- 0.3 to 0.8 a frame
      if t % 2 == 1 then
        m.vx = m.vx + wa.random(-19661, 19661) -- up to 0.3 either way
      end
      nr_climbing[m.id] = { x = m.x, y = m.y, vx = m.vx, vy = m.vy }
      for _, w in ipairs(wa.worms.all()) do
        if near(w.x, w.y, m.x, m.y) then
          w.vx, w.vy = m.vx, m.vy
        end
      end
    else
      nr_climbing[m.id] = nil
      if m.vy < 0 then
        m.vy = m.vy + 13107 -- 0.2: slows the climb without faking gravity
      end
    end
    nr_nuke[m.id] = t + 1
    return
  end
  -- The rocket is the missile WA fires after the fire key. Later ones of
  -- the slot (the nuke's cluster bits) are no rockets.
  if nr_first[m.id] == nil and nr_expect and m.weapon == "mine" then
    nr_first[m.id], nr_expect = 0, false
  end
  if nr_first[m.id] ~= nil then
    if m.phase == "post" then
      nr_speed[m.id] = { m.vx, m.vy }
      local n = (nr_first[m.id] or 0) + 1
      nr_first[m.id] = n
      if n % 10 == 0 and nr_shooter then
        wa.sound.play(nr_shooter, NR_HISS)
      end
    end
    return
  end
  -- Any other missile a climbing nuke passes is carried along.
  if m.phase == "pre" then
    for _, c in pairs(nr_climbing) do
      if near(m.x, m.y, c.x, c.y) then
        m.vx, m.vy = c.vx, c.vy
      end
    end
  end
end)

nuke_rocket_explode = function(ev)
  local id = ev.missile
  if not id then
    return
  end
  if nr_nuke[id] then
    nr_nuke[id], nr_climbing[id] = nil, nil
    local owner = nr_shooter
    if owner then
      wa.sound.play(owner, 85)
      wa.sound.play(owner, 70) -- "louder please :D"
      for _ = 1, 2 do
        wa.actors.spawn({
          sprite = false, x = ev.x, y = ev.y, owner = owner,
          explode = { damage = NUKE_BLAST.damage, id = NUKE_BLAST.id, now = true },
        })
      end
    end
    return
  end
  if nr_first[id] then
    local speed = nr_speed[id] or { 0, 0 }
    nr_first[id], nr_speed[id] = nil, nil
    if nr_shooter then
      wa.sound.play(nr_shooter, "sounds/nuke_rocket_launch.wav")
    end
    -- Launched after the blast, as PX's comes after super.
    nr_pending[#nr_pending + 1] = { x = ev.x, y = ev.y, vx = speed[1], vy = speed[2] }
  end
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FIRE_WEAPON and worm.weapon == "mine" then
    nr_shooter, nr_expect = worm, true
  elseif msg == wa.msg.FRAME_FINISH and #nr_pending > 0 then
    local owner = nr_shooter or worm
    for _, p in ipairs(nr_pending) do
      local id = wa.weapons.launch({
        weapon = "mine", owner = owner, x = p.x, y = p.y, vx = p.vx, vy = p.vy,
        fuse = NUKE.fuse, sound = NUKE.sound, explode_into = NUKE.explode_into,
      })
      nr_nuke[id] = 0
    end
    nr_pending = {}
  end
end)
end

-- -------------------------------------------------------------- Helicopter
-- Shared with later sections; the rest of this section is local to it.
local FX, trunc
do
--
-- PX's helicopter_user_script, on WA's jet pack. While the jet pack runs,
-- the script flies the worm itself from the worm's own move keys. The engine
-- consumes them after this callback, so WA neither thrusts nor burns fuel.
-- Speed builds while a key is held and dies away when it is not; fuel burns
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
FX = 0x10000

local helis = {} -- worm id -> { flying, launch, jumpin, jump_phase, frame, ticks, body, climb }

function trunc(v)
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
    worm:jetpack_steer(true)
    h.flying, h.launch, h.ticks, h.armed = true, true, 0, false
  elseif h and h.armed and not worm.turn then
    h.armed = false -- the turn ended before it fired
  end
  if not h then
    return
  end
  if h.flying then
    if state ~= "jetpacking" then
      -- WA owns the landing and its resulting state. Only remove our art
      -- and physics overrides when WA has ended the jet pack.
      worm:jetpack_steer(false)
      worm.gravity, worm.wind = FX, 0
      h.flying = false
      heli_drop_art(h, worm)
      return
    end
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
    worm.vx, worm.vy, worm.fuel = trunc(vx), trunc(vy), trunc(fuel)
    if worm.fuel <= 0.1 * FX then
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
end

-- Shared by the balloon and glider handlers to recognize the equipped weapon.
local balloons = {}

-- --------------------------------------------------------- Hot Air Balloon
do
  --
  -- PX's balloon_s (r2_balloon by rafa''2, modified by 0rang3). PX flies it on
  -- WA's parachute with the worm's gravity turned upside down; here the pack
  -- flies it (worm:take) with WA's own parachute physics, upside down. WA 3.8.1,
  -- per frame (0x4FCB30): the speed gains gravity times the worm's gravity
  -- factor and, unless the worm is against land beside it, the wind times its
  -- wind factor; then both speeds are damped. Its parachute (SetState 0x7D at
  -- 0x50EBE2 and 0x50EC57) damps them to 0.8 and takes the wind factor from the
  -- weapon record's +0x38 in percent: the patched bungee's fire_method, 100.
  -- So it rises at up to four times gravity and drifts with four times the
  -- wind. The arrow keys push it as they push WA's parachute (0x513EB0, run
  -- before that step): half of gravity a frame each way held (through the
  -- worm's +0x44 push, divided by its mass, 1.0), opposite keys cancelling. It pops -- the worm given back to WA, falling -- on touching land,
  -- in water, on the jump key (which closes WA's parachute), and when the
  -- turn ends. The worm's body is hidden behind the balloon, drawn in its
  -- team's colour, and the worm in its basket, as PX's RenderWorm override.
  --
  -- It still opens as WA's parachute (the patched bungee, by hand or
  -- automatically); the pack takes the worm on the first frame of it.

  local BALLOON_DAMP = 0xCCCC       -- WA's parachute damping, 0.8
  local BALLOON_WIND = 100          -- the patched bungee's fire_method, in percent
  local BALLOON_DEPTH = 0x10001     -- behind the basket, in front of worms
  local BASKET_DEPTH = 0x10000
  -- PX's GetTeamColorRGB, by WA's colour index (worm.alliance, 0 red .. 5 cyan).
  -- PX adds it to its dark grey balloon (SetColorMod mode 8); the GPU tint
  -- multiplies, so the pack's balloon art is PX's lightened to white, and the
  -- team colour shows at full strength.
  local TEAM_RGB = { 0xFF8080, 0x0096FF, 0x00D000, 0xFFFF40, 0xE800E8, 0x50FFFF }

  -- Also records the weapon equipped before WA changes the visible slot while
  -- opening a parachute, for both the balloon and glider handlers.
  -- worm id -> { active, x, y, vx, vy, ticks, equipped_weapon, balloon, basket }

  local function balloon_of(worm)
    local b = balloons[worm.id]
    if not b then
      b = { active = false, ticks = 0 }
      balloons[worm.id] = b
    end
    return b
  end

  local function balloon_sound(worm, name, n)
    wa.sound.play(worm, "sounds/balloon/" .. name .. wa.random(1, n) .. ".wav")
  end


  -- How many frames after popping against land the worm is watched: WA may
  -- stand it up there, in mid-air under a ceiling.
  local BALLOON_UNSTAND = 3

  -- StopBalloon: a pop, and the worm back to WA, falling with its speed.
  -- Against land it keeps no upward speed, and for a few frames, if WA has
  -- stood it up, it is released again, falling: PX's balloon does the same
  -- (WS_IDLE -> WS_SLIDING) when WA's parachute closes against the land.
  local function balloon_stop(worm, b, against_land)
    if not b.active then
      return
    end
    b.active, b.ticks = false, 0
    if b.balloon then b.balloon:despawn(); b.balloon = nil end
    if b.basket then b.basket:despawn(); b.basket = nil end
    worm.body_visible = true
    balloon_sound(worm, "pop", 4)
    local vy = against_land and math.max(b.vy, 0) or b.vy
    if worm.taken then
      worm:release(b.vx, vy)
    end
    b.unstand = against_land and BALLOON_UNSTAND or nil
  end

  local function balloon_draw(worm, b)
    -- DrawBalloonWorm: the balloon above, in the team's colour, and the worm
    -- in its basket, whose art faces left.
    local f = worm.facing
    local function art(sheet)
      return wa.actors.spawn({
        sprite = sheet, x = b.x, y = b.y, gravity = false,
        collide = false, owner = worm, on = function() end,
      })
    end
    b.balloon = b.balloon or art("sprites/balloon/balloon")
    b.basket = b.basket or art("sprites/balloon/basket")
    local x = b.x + 6 * f * FX
    b.balloon.x, b.balloon.y, b.balloon.vx, b.balloon.vy = x, b.y - 43 * FX, 0, 0
    b.balloon:frame(math.min((b.ticks % 200) * 16 // 200, 15))
    b.balloon:gfx({ tint = 0xFF000000 | (TEAM_RGB[(worm.alliance or 0) + 1] or 0xFFFFFF),
      depth = BALLOON_DEPTH })
    b.basket.x, b.basket.y, b.basket.vx, b.basket.vy = x, b.y + 3 * FX, 0, 0
    b.basket.facing = -f
    b.basket:frame(math.min((b.ticks % 80) * 17 // 80, 16))
    b.basket:gfx({ depth = BASKET_DEPTH })
    worm.body_visible = false
  end

  local function balloon_frame(worm)
    local b = balloon_of(worm)
    local state = worm.state
    -- WA may change the selected slot to Parachute (or none) as Bungee fires.
    -- The weapon equipped before that transition identifies the auto trigger;
    -- an unrelated parachute opening must not become a Hot Air Balloon.
    local equipped = b.equipped_weapon
    if not b.active and state == "parachuting" and not b.was_parachuting
        and equipped == "bungee" then
      b.active, b.ticks = true, 0
      b.x, b.y, b.vx, b.vy = worm.x, worm.y, worm.vx, worm.vy
      worm:take{ turn = "run" }
      balloon_sound(worm, "inflate", 3)
    end
    b.was_parachuting = state == "parachuting"
    if state ~= "parachuting" then b.equipped_weapon = worm.weapon end
    if b.unstand then
      if state == "standing" then
        worm:release(0, 0)
        b.unstand = nil
      else
        b.unstand = b.unstand > 1 and b.unstand - 1 or nil
      end
    end
    if not b.active then
      return
    end
    -- The engine let go: the turn ended, or WA knocked the worm flying.
    if not worm.taken then
      balloon_stop(worm, b)
      return
    end
    local P = 0x10000
    local vx, vy = b.vx, b.vy
    -- The arrow keys, as WA's parachute takes them (0x514AC0, 0x513EB0).
    local k = worm.keys or {}
    local left, right, up, down = k.left, k.right, k.up, k.down
    if left and right then left, right = false, false end
    if up and down then up, down = false, false end
    local g = wa.world.gravity()
    local push = g >= 0 and g // 2 or -(-g // 2)
    vx = vx + (right and push or 0) - (left and push or 0)
    vy = vy + (down and push or 0) - (up and push or 0)
    -- WA's parachute physics, gravity upside down (0x4FCB30).
    vy = vy - g * worm.gravity // P
    local side = wa.world.wind() >= 0 and P or -P
    if worm:fits(b.x + side, b.y) then
      vx = vx + wa.world.wind() * (BALLOON_WIND * P // 100) // P
    end
    vx, vy = vx * BALLOON_DAMP // P, vy * BALLOON_DAMP // P
    b.vx, b.vy = vx, vy
    local x, y = b.x + vx, b.y + vy
    -- It pops on touching land, as WA's parachute closes there: where WA's
    -- own test says the worm would touch it, so it never sits inside it.
    if not worm:fits(x, y) then
      balloon_stop(worm, b, true)
      return
    end
    if y >= wa.world.water() then
      balloon_stop(worm, b)
      return
    end
    b.x, b.y = x, y
    worm:carry(x, y)
    b.ticks = b.ticks + 1
    balloon_draw(worm, b)
  end

  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FRAME_FINISH then
      balloon_frame(worm)
      return
    end
    local b = balloons[worm.id]
    if not (b and b.active) then
      return
    end
    if msg == wa.msg.JUMP then
      -- The jump key closes WA's parachute: here it pops the balloon.
      balloon_stop(worm, b)
      return "eat"
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
end

-- ------------------------------------------------------------- Hang-Glider
do
  --
  -- PX's paratest (utility_hangglider_render). A worm that opens WA's
  -- parachute with the Hang-Glider flies PX's glider instead: the pack takes
  -- it (worm:take) and moves it with the glider's physics: gravity at 0.75,
  -- the wind blowing along the wing's up side (x3), the speed across the wing
  -- damped, and the nose turning towards the flight path. Up and down turn the
  -- nose, faster the faster it flies; left and right nudge it. Just before it
  -- would run into something (PX's WS_AFTERROPE), on the jump key, in water,
  -- or when the turn ends, it gives the worm back to WA, falling on with the
  -- glider's speed; WA lands it. While it glides, the worm's body is hidden
  -- behind the glider art, which carries the worm; brought down onto land,
  -- the glider's own pack-away plays once WA has the worm standing (PX swaps
  -- sheet 289, wparbak, for it).
  --
  -- PX's speeds and angles are pixels per frame and radians; WA's gravity,
  -- wind and worm speeds are 16.16.

  local GLIDER_GRAVITY = 0.75           -- GliderGravityFactor
  local GLIDER_WIND = 3.0               -- GliderWindFactor
  local GLIDER_FRICTION = 0.25          -- GliderFriction
  local GLIDER_TURN = 0.06              -- GliderMaxAngularVelocity
  local GLIDER_TURN_SPEED = 20.0        -- GliderMaxTurningSpeed
  local GLIDER_ANIM = 0.04              -- GliderAnimSpeed
  local GLIDER_LERP = 0.03              -- GliderRotationLerp
  local GLIDER_PUSH = 0.02              -- GliderMoveAcceleration
  local GLIDER_MAX_ANGLE = 1.5          -- about 86 degrees either way
  local GLIDER_DEPTH = 0x10000          -- in front of worms and terrain
  -- wgldbak: 6 frames, loaded at 24 frames a second; WA runs 50.
  local GLIDER_PACK_FRAMES, GLIDER_PACK_FPS = 6, 24
  -- How long after coming down onto land WA may take to stand the worm up for
  -- the pack-away (frames).
  local GLIDER_PACK_WAIT = 50
  -- WA's fall damage begins at 8 pixels/frame of downward impact speed. Its
  -- fixed-point formula includes one 16.16 unit of bias.
  local GLIDER_SAFE_LANDING_SPEED = 8 * 0x10000 - 1
  local GLIDER_PI = 3.141593

  local gliders = {} -- worm id -> { enabled, deployed, x, y, ang, target, cycle, sx, sy, art, pack, pack_t, landing }

  local function glider_of(worm)
    local g = gliders[worm.id]
    if not g then
      g = { enabled = false, deployed = false, ang = 0, target = 0, cycle = 0, sx = 0, sy = 0 }
      gliders[worm.id] = g
    end
    return g
  end

  -- utils' NormalizeAngle and LerpAngle.
  local function normalize_angle(a)
    while a > GLIDER_PI do a = a - 6.283186 end
    while a <= -GLIDER_PI do a = a + 6.283186 end
    return a
  end

  local function lerp_angle(c, a, b)
    a = normalize_angle(a)
    b = a + normalize_angle(b - a)
    return normalize_angle(a + (b - a) * c)
  end

  local function glider_art(worm, x, y, sheet)
    return wa.actors.spawn({
      sprite = sheet, x = x, y = y, gravity = false,
      collide = false, owner = worm, on = function() end,
    })
  end

  local function glider_drop_art(worm, g)
    if g.art then g.art:despawn(); g.art = nil end
    if g.pack then g.pack:despawn(); g.pack = nil end
    g.pack_x, g.pack_y = nil, nil
    worm.body_visible = true
  end

  local function glider_begin_pack(worm, g)
    g.landing = nil
    if g.art then g.art:despawn(); g.art = nil end
    g.pack, g.pack_t = glider_art(worm, worm.x, worm.y, "sprites/hang_glider/pack"), 0
    g.pack_x, g.pack_y = worm.x, worm.y
    g.pack.facing = -worm.facing
    g.pack:frame(0)
    g.pack:gfx({ depth = GLIDER_DEPTH })
    worm.body_visible = false
  end

  -- TraceMask from (x, y) to where it is heading: anything the worm would
  -- touch there by WA's own test of its shape (worm:fits, every 2 pixels),
  -- and anything else in the way by the Sniper Rifle's estimate of its mask.
  local function glider_blocked(worm, x, y, sx, sy)
    local P = 0x10000
    local x1, y1 = x + trunc(1.1 * sx * P), y + trunc(1.1 * sy * P)
    local n = math.max(1, math.ceil(math.sqrt(sx * sx + sy * sy) * 1.1 / 2))
    for i = 1, n do
      if not worm:fits(x + (x1 - x) * i // n, y + (y1 - y) * i // n) then
        return true
      end
    end
    local len = math.sqrt(sx * sx + sy * sy) * 1.1
    if len == 0 then
      return false
    end
    local dx, dy = sx * 1.1 / len, sy * 1.1 / len
    for _, s in ipairs(STOPPERS) do
      local list, r = s[1], s[2]
      if list and list.all then
        for _, o in ipairs(list.all()) do
          if o.id ~= worm.id then
            local ox, oy = (o.x - x) / P, (o.y - y) / P
            local t = ox * dx + oy * dy
            if t > 0 and t < len and math.abs(ox * dy - oy * dx) < r then
              return true
            end
          end
        end
      end
    end
    return false
  end

  -- CWormGlider::Move: up and down turn the nose, left and right push.
  local function glider_keys(worm, g)
    local k = worm.keys
    local speed = math.sqrt(g.sx * g.sx + g.sy * g.sy) / GLIDER_TURN_SPEED
    if k.up then
      g.ang = math.max(g.ang - GLIDER_TURN * math.min(speed, 1), -GLIDER_MAX_ANGLE)
    end
    if k.down then
      g.ang = math.min(g.ang + GLIDER_TURN * math.max(math.min(speed, 1), 0.5), GLIDER_MAX_ANGLE)
    end
    if k.left then g.sx = g.sx - GLIDER_PUSH end
    if k.right then g.sx = g.sx + GLIDER_PUSH end
  end

  -- CWormGlider::Think's physics, once deployed: the new speed.
  local function glider_think(worm, g)
    local P = 0x10000
    local f = worm.facing
    local ang = f < 0 and g.ang or GLIDER_PI - g.ang
    local fwd_x, fwd_y = -math.cos(ang), math.sin(ang)
    local up_x, up_y
    if f < 0 then up_x, up_y = -fwd_y, fwd_x else up_x, up_y = fwd_y, -fwd_x end
    local sx, sy = g.sx, g.sy
    sy = sy + wa.world.gravity() / P * GLIDER_GRAVITY
    local wind = up_x * wa.world.wind() / P * GLIDER_WIND
    sx, sy = sx + wind * up_x, sy + wind * up_y
    local up_vel = sx * up_x + sy * up_y
    sx, sy = sx - up_x * up_vel * GLIDER_FRICTION, sy - up_y * up_vel * GLIDER_FRICTION
    -- The nose turns towards the flight path, never straight up or down.
    local target = f < 0 and math.atan(sy, -sx) or math.atan(sy, sx)
    target = normalize_angle(target)
    g.target = math.max(-GLIDER_MAX_ANGLE, math.min(GLIDER_MAX_ANGLE, target))
    g.ang = lerp_angle(GLIDER_LERP, g.ang, g.target)
    g.cycle = math.min(g.cycle + GLIDER_ANIM, 1)
    g.sx, g.sy = sx, sy
  end

  -- How many frames after a crash the worm is watched: WA may stand it up
  -- where it hit, as it does a balloon popped against a ceiling.
  local GLIDER_UNSTAND = 3

  -- The glide ends: the worm back to WA, falling on with the glider's speed.
  -- `landing`: a gentle landing, so the pack-away plays once WA has the worm
  -- standing. A hard landing gives WA the glider's full speed in its
  -- falling state and lets WA decide whether it causes fall damage and loss
  -- of control. Suppress automatic parachute firing only until WA handles
  -- this impact; otherwise it immediately reopens and slows the worm.
  -- Only a collision
  -- elsewhere needs the short guard against WA standing it up in mid-air.
  local function glider_close(worm, g, landing, hard_landing)
    local P = 0x10000
    g.deployed = false
    -- A gentle landing can spend several frames falling under WA's control
    -- before WA stands the worm up. Keep the wing over its body until the
    -- pack-away takes its place, so it never flashes empty-handed.
    if landing then
      g.art = g.art or glider_art(worm, worm.x, worm.y, "sprites/hang_glider/glider")
      worm.body_visible = false
    else
      glider_drop_art(worm, g)
    end
    wa.sound.play(worm, "sounds/hang_glider/hangclose.wav")
    g.landing = landing and GLIDER_PACK_WAIT or nil
    g.unstand = not (landing or hard_landing) and GLIDER_UNSTAND or nil
    if worm.taken then
      local vx, vy = trunc(g.sx * P), trunc(g.sy * P)
      if hard_landing then
        worm:release(vx, vy, { suppress_auto_parachute = true })
      else
        worm:release(vx, vy)
      end
    end
  end

  local function glider_frame(worm)
    local state = worm.state
    local b = balloons[worm.id]
    local equipped = b and b.equipped_weapon
    if b and b.active then
      local g = gliders[worm.id]
      if g then g.enabled = false end
      return
    end
    -- A glider may have auto-opened and cleared its selected slot before its
    -- first frame. The slot equipped before opening is authoritative.
    local g = gliders[worm.id]
    if not g then
      if (state == "parachuting" and equipped ~= "parachute")
          or (state ~= "parachuting" and worm.weapon ~= "parachute") then
        return
      end
      g = glider_of(worm)
    end
    local P = 0x10000
    if g.deployed then
      -- The engine let go: the turn ended, or WA knocked the worm flying.
      if not worm.taken then
        glider_close(worm, g, false)
        return
      end
      glider_keys(worm, g)
      glider_think(worm, g)
      if glider_blocked(worm, g.x, g.y, g.sx, g.sy) then
        -- Onto land below it: WA handles the impact with the glider's full
        -- speed. Only a fall below its damage threshold gets the pack-away.
        local below = g.sy > 0 and not worm:fits(g.x, g.y + trunc((1.1 * g.sy + 4) * P))
        local hard_landing = below and trunc(g.sy * P) >= GLIDER_SAFE_LANDING_SPEED
        glider_close(worm, g, below and not hard_landing, hard_landing)
        return
      end
      local x, y = g.x + trunc(g.sx * P), g.y + trunc(g.sy * P)
      if y >= wa.world.water() then
        glider_close(worm, g, false)
        return
      end
      g.x, g.y = x, y
      worm:carry(x, y)
      -- CWormGlider::Render, in the worm's place.
      local f = worm.facing
      g.art = g.art or glider_art(worm, x, y, "sprites/hang_glider/glider")
      local a = g.art
      a.x, a.y, a.vx, a.vy, a.facing = x, y, 0, 0, -f
      a:frame(math.min(math.floor(g.cycle * 10), 9))
      a:gfx({ angle = math.deg(f * g.ang) % 360, depth = GLIDER_DEPTH })
      worm.body_visible = false
      return
    end
    if state ~= "parachuting" then
      -- Which parachute the worm opens next: PX checks the weapon only while
      -- the worm is not already under one.
      g.enabled = worm.weapon == "parachute"
      if g.unstand then
        if state == "standing" then
          worm:release(0, 0)
          g.unstand = nil
        else
          g.unstand = g.unstand > 1 and g.unstand - 1 or nil
        end
      end
      -- A land contact starts the pack-away in that frame. Standing is a
      -- fallback if WA did not report a contact; it may arrive 12 frames later.
      if g.landing then
        if state == "standing" and worm.y < wa.world.water() then
          glider_begin_pack(worm, g)
        elseif worm.y >= wa.world.water() or state == "tumbling" then
          g.landing = nil
          glider_drop_art(worm, g)
        else
          g.landing = g.landing > 1 and g.landing - 1 or nil
          if g.landing and g.art then
            g.art.x, g.art.y, g.art.vx, g.art.vy = worm.x, worm.y, 0, 0
            g.art.facing = -worm.facing
            worm.body_visible = false
          else
            glider_drop_art(worm, g)
          end
        end
      end
      if g.pack then
        local frame = g.pack_t * GLIDER_PACK_FPS // 50
        local keys = worm.keys or {}
        local moving = keys.left or keys.right or state == "walking"
          or state == "jump_prepare" or state == "jumping"
          or math.abs(worm.x - g.pack_x) > P
        local landing_state = state == "standing" or state == "sliding"
          or state == "jump_falling" or state == "falling"
        if frame >= GLIDER_PACK_FRAMES or moving or not landing_state
            or worm.y >= wa.world.water() then
          glider_drop_art(worm, g)
        else
          g.pack.x, g.pack.y, g.pack.vx, g.pack.vy = worm.x, worm.y, 0, 0
          g.pack.facing = -worm.facing -- its art faces left, as WA's worms do
          g.pack:frame(frame)
          g.pack:gfx({ depth = GLIDER_DEPTH })
          worm.body_visible = false
          g.pack_t = g.pack_t + 1
        end
      end
      -- Its speed carries over into the glide.
      g.sx, g.sy = worm.vx / P, worm.vy / P
      return
    end
    g.enabled = equipped == "parachute"
    if not g.enabled or g.deployed or state ~= "parachuting" then
      return -- a plain parachute, or the balloon
    end
    -- WA has opened its parachute: the pack takes the worm and glides.
    g.deployed, g.ang, g.target, g.cycle, g.landing, g.unstand = true, 0, 0, 0, nil, nil
    g.x, g.y = worm.x, worm.y
    if g.pack then g.pack:despawn(); g.pack = nil end
    worm:take{ turn = "run" }
    wa.sound.play(worm, "sounds/hang_glider/hangopen.wav")
    return glider_frame(worm)
  end

  if wa.world.gravity and wa.world.wind then
    if wa.on.contact then
      wa.on.contact(function(worm, other)
        local g = gliders[worm.id]
        if g and g.landing and other.kind == "land" and worm.y < wa.world.water() then
          local keys = worm.keys or {}
          if keys.left or keys.right then
            g.landing = nil
            glider_drop_art(worm, g)
          else
            glider_begin_pack(worm, g)
          end
        end
      end)
    end
    wa.on.worm_message(function(worm, msg)
      if msg == wa.msg.FRAME_FINISH then
        glider_frame(worm)
        return
      end
      local g = gliders[worm.id]
      if g and g.pack and (msg == wa.msg.JUMP or msg == wa.msg.JUMP_UP) then
        glider_drop_art(worm, g)
        return
      end
      if not (g and g.deployed) then
        return
      end
      if msg == wa.msg.JUMP then
        -- The jump key closes WA's parachute: here it lets go of the glider.
        glider_close(worm, g, false)
        return "eat"
      end
    end)
  end
end

-- --------------------------------------------------------------- Swim Suit
do
--
-- PX's swimsuit_SCRIPT (StepS; swim sprites by Team17) with fastswim_SCRIPT
-- and swim_suit_diving_s (PyroMan), on WA's laser sight. Using it puts the
-- suit on (or, out of the water, takes it off): WA's laser sight never
-- switches on, as PX's FireFinal never calls super. A worm in the suit that
-- falls into the water splashes and swims instead of drowning: the pack takes
-- it (worm:take) and moves it by its own four keys (up to 2.5 pixels a frame
-- times the swim speed, gliding to a stop when they are let go), stopping at
-- land, turned by left and right unless Shift is held. Enter and weapons do
-- nothing while it swims (Fast Walk aside). Out of the water it is released
-- as from a jump. Too deep (180 pixels under the water, or the bottom of a
-- cavern), knocked flying, or still in the water when the turn ends, the
-- suit gives out and it drowns. Fast Walk switches the swim speed between 2
-- and 6 for the turn. Missiles in the water can hit a swimming worm: they
-- blow up on it (damage 100, blast 50).
--
-- Drawn in the worm's place: the swim or, when still, the float animation,
-- and a bubble around the worm while it wears the suit.
--
-- Not ported: PX's ghost jet and battyswim interplay (other libraries), the
-- Ninja Rope workaround after leaving the water (the Jump is on the rope's
-- slot here), inverted controls, and the team message on putting it on.

local SWIM_CAP = 2.5          -- pixels a frame, times the swim speed
local SWIM_PUSH = 0.1
local SWIM_DRAG = 1.05
local SWIM_STILL = 0.05
local SWIM_FLOAT_STEP = 0.0099
local SWIM_DEPTH = 180        -- how far under the water the suit holds
local SWIM_SUIT_MASK = 134342 -- 0x20CC6: the worm's 0x420CC6 without SWIM_WATER
-- Bit 22 of a collision mask: WA's water acts on what has it (0x4FDE20), and
-- sinks or drowns it. The suit takes it off; a missile sinking in the water
-- has only it.
local SWIM_WATER = 0x400000
local SWIM_MISSILE_MASK = 0x40007C -- a missile in the water that hits worms
local SWIM_SPLASH = 57        -- WA's sound
local SWIM_BODY_DEPTH = 0x10000
local SWIM_RING_DEPTH = 0x10001
-- Ring sheet is 50×50; wa.draw.quad corners are centred on the worm like a:gfx.
local SWIM_RING_HALF = 25 * 0x10000
-- The land a swimmer stops at: its body, 4 pixels either side, 6 above and below.
local SWIM_HALF_W, SWIM_HALF_H = 4 * 0x10000, 6 * 0x10000

local swim_speed = 2          -- fastswim: Fast Walk switches 2 and 6
local swim_in_game = false    -- SwimInGame: someone has worn the suit
local swimmers = {} -- worm id -> { suit, plopready, plopped, floating, plophase, flophase, fmult, keys, body, x, y, vx, vy }

local function swimmer_of(worm)
  local s = swimmers[worm.id]
  if not s then
    s = { suit = false, plopready = false, plopped = false, floating = false,
      plophase = 0, flophase = 0, fmult = 5, keys = {} }
    swimmers[worm.id] = s
  end
  return s
end

local function swim_drop_art(worm, s)
  if s.body then s.body:despawn(); s.body = nil end
  worm.body_visible = true
end

-- The suit comes off, the water's bit back in its mask. `sink`: it gave out
-- in the water, and the worm goes back to WA out of control, moving at
-- (vx, vy), for WA to drown.
local function suit_off(worm, s, sink, vx, vy)
  s.suit, s.plopready, s.plopped, s.floating = false, false, false, false
  swim_drop_art(worm, s)
  if sink then
    worm:release(vx, vy, { tumble = true })
  end
  worm.collision_mask = worm.collision_mask | SWIM_WATER
end

local function swim_blocked(x, y)
  return wa.land.solid(x - SWIM_HALF_W, y) or wa.land.solid(x + SWIM_HALF_W, y)
    or wa.land.solid(x, y - SWIM_HALF_H) or wa.land.solid(x, y + SWIM_HALF_H)
end

-- One step towards the cap on a held key, as PX's: while under it, a push;
-- past it, back to it.
local function swim_push(v, dir, cap)
  if dir > 0 then
    if v < cap then return v + SWIM_PUSH * swim_speed end
    return cap
  end
  if v > -cap then return v - SWIM_PUSH * swim_speed end
  return -cap
end

local function swim_frame(worm)
  local s = swimmers[worm.id]
  if not s or not s.suit then
    return
  end
  local P = 0x10000
  local water = wa.world.water()
  local cap = SWIM_CAP * swim_speed
  if worm.y >= water and s.plopready and worm.state ~= "teleporting" then
    wa.sound.play(worm, SWIM_SPLASH)
    s.plopready, s.plopped = false, true
    s.x, s.y = worm.x, worm.y
    s.vx, s.vy = math.min(worm.vx / P, cap), math.min(worm.vy / P, cap)
    worm:take{ turn = "run" }
    s.plophase = 0
  end
  if s.plopped and not worm.taken then
    -- The engine let go: the turn ended, or WA knocked it flying. Still in
    -- the water, the suit gives out.
    suit_off(worm, s, true, worm.vx, worm.vy)
    return
  end
  if s.plopped then
    local vx, vy = math.min(s.vx, cap), math.min(s.vy, cap)
    local held = s.keys
    local still = math.abs(vx) <= SWIM_STILL * swim_speed and math.abs(vy) <= SWIM_STILL * swim_speed
    if still and not (held.left or held.up or held.down or held.right) then
      -- Floating: the float animation, back and forth.
      s.floating = true
      s.flophase = s.flophase + SWIM_FLOAT_STEP * s.fmult
      if s.flophase >= 0.99 and s.fmult == 5 then
        s.flophase, s.fmult = 0.99, -5
      elseif s.flophase <= 0 and s.fmult == -5 then
        s.flophase, s.fmult = 0, 5
      end
    elseif vx ~= 0 and vy ~= 0 then
      -- Swimming: the stroke follows the faster of the two directions.
      s.floating = false
      if math.abs(vx) >= math.abs(vy) then
        s.plophase = s.plophase + SWIM_FLOAT_STEP * vx * worm.facing
      else
        s.plophase = s.plophase - SWIM_FLOAT_STEP * vy
      end
    elseif vx ~= 0 then
      s.floating = false
      s.plophase = s.plophase + SWIM_FLOAT_STEP * vx
    elseif vy ~= 0 then
      s.floating = false
      s.plophase = s.plophase - SWIM_FLOAT_STEP * vy
    end
    if s.plophase >= 1 or s.plophase <= -1 then
      s.plophase = 0
    end
    local k = worm.keys
    local up, down, left, right = k.up, k.down, k.left, k.right
    if up == down then vy = vy / SWIM_DRAG end
    if left == right then vx = vx / SWIM_DRAG end
    if up then vy = swim_push(vy, -1, cap) end
    if down then vy = swim_push(vy, 1, cap) end
    local shift = wa.world.keys().sprint
    if left then
      if not shift then worm.facing = -1 end
      vx = swim_push(vx, -1, cap)
    end
    if right then
      if not shift then worm.facing = 1 end
      vx = swim_push(vx, 1, cap)
    end
    s.keys = { up = up, down = down, left = left, right = right }
    -- The engine clears the keys after this hook. Move, stopping at land
    -- on each axis (unless it is already in land, so it can swim free).
    local stuck = swim_blocked(s.x, s.y)
    local nx = s.x + trunc(vx * P)
    if not stuck and swim_blocked(nx, s.y) then vx = 0 else s.x = nx end
    local ny = s.y + trunc(vy * P)
    if not stuck and swim_blocked(s.x, ny) then vy = 0 else s.y = ny end
    s.vx, s.vy = vx, vy
    -- Out of the water: on through the air, as from a jump.
    if s.y < water then
      s.floating = false
      s.plopready, s.plopped = true, false
      -- Where the swim took it: its last pin is still under the surface.
      worm.x, worm.y = s.x, s.y
      worm:release(trunc(vx * P), trunc(vy * P))
    else
      worm:carry(s.x, s.y)
      -- Too deep: the suit gives out.
      local y, w = s.y / P, water / P
      local deep
      if not wa.world.cavern() then
        deep = y > w + SWIM_DEPTH
      elseif w > 610 then
        deep = y > w + SWIM_DEPTH
      else
        deep = y > 768
      end
      if deep then
        suit_off(worm, s, true, trunc(vx * P), trunc(vy * P))
        return
      end
    end
  end
  -- Between turns, a worm out of the water takes the suit off.
  if not current_worm() and worm.y < water then
    suit_off(worm, s, false)
    return
  end
  -- RenderWorm: in the water, the swim or float animation in the worm's
  -- place (its art faces left). The bubble is drawn at render time below.
  local function art(sheet)
    return wa.actors.spawn({
      sprite = sheet, x = worm.x, y = worm.y, gravity = false,
      collide = false, owner = worm, on = function() end,
    })
  end
  if s.plopped then
    local sheet = s.floating and "sprites/swim_suit/float" or "sprites/swim_suit/swim"
    if s.body and s.body_sheet ~= sheet then
      s.body:despawn()
      s.body = nil
    end
    s.body = s.body or art(sheet)
    s.body_sheet = sheet
    local phase = s.floating and s.flophase or s.plophase
    s.body.x, s.body.y, s.body.vx, s.body.vy = s.x, s.y, 0, 0
    s.body.facing = -worm.facing
    s.body:frame(math.floor((phase % 1) * 20) % 20)
    s.body:gfx({ depth = SWIM_BODY_DEPTH })
    worm.body_visible = false
  elseif s.body then
    s.body:despawn()
    s.body = nil
    worm.body_visible = true
  end
end

-- Bubble while the suit is worn: draw-only, from the live worm position each
-- rendered frame (keeps the 16.16 fraction). A follower LuaActor + a:gfx was
-- pixel-snapped and could wobble when airborne.
if wa.on.draw then
  wa.on.draw(function()
    for _, worm in ipairs(wa.worms.all()) do
      local s = swimmers[worm.id]
      if s and s.suit then
        local x, y, h = worm.x, worm.y, SWIM_RING_HALF
        wa.draw.quad({
          points = {
            { x - h, y - h }, { x + h, y - h }, { x + h, y + h }, { x - h, y + h },
          },
          sprite = "sprites/swim_suit/ring",
          depth = SWIM_RING_DEPTH,
        })
      end
    end
  end)
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FRAME_FINISH then
    swim_frame(worm)
  elseif msg == wa.msg.JUMP then
    -- M_ENTER: no jumping while it swims.
    local s = swimmers[worm.id]
    if s and s.plopped then
      return "eat"
    end
  elseif msg == wa.msg.FIRE_WEAPON then
    local s = swimmers[worm.id]
    if s and s.plopped and worm.weapon ~= "fast_walk" then
      return "eat" -- no weapons while it swims
    end
    if worm.weapon == "fast_walk" then
      swim_speed = swim_speed ~= 6 and 6 or 2
    elseif worm.weapon == "laser_sight" then
      -- FireFinal(Swim Suit), in place of WA's laser sight.
      local s = swimmer_of(worm)
      if not s.suit then
        wa.sound.play(worm, "sounds/swim_suit/putting_on_ssuit.wav")
        s.suit, s.plopready = true, true
        swim_in_game = true
        worm.collision_mask = SWIM_SUIT_MASK
      elseif worm.y < wa.world.water() then
        suit_off(worm, s, false)
      end
      worm:ammo("laser_sight", -1)
      return "eat"
    end
  end
end)

-- fastswim: the swim speed is 2 again every turn.
wa.on.turn_start(function()
  swim_speed = 2
end)

-- A missile in the water hits worms too, once anyone has worn the suit.
wa.on.missile_frame(function(m)
  if swim_in_game and m.phase == "pre" and m.collision_mask == SWIM_WATER then
    m.collision_mask = SWIM_MISSILE_MASK
  end
end)

-- CMissile::Collide: such a missile blows up on a swimming worm, and is gone
-- (sent below the water, where WA frees it).
if wa.on.contact then
  wa.on.contact(function(worm, other)
    local s = swimmers[worm.id]
    if s and s.plopped and other.kind == "missile" then
      wa.actors.spawn({
        sprite = false, x = other.x, y = other.y, gravity = false, collide = false,
        owner = worm, explode = { damage = 100, id = 50, now = true },
      })
      other.y = wa.world.water() + 0x10000 * 4096
    end
  end)
end
end

-- ---------------------------------------------- Wind Changer, Gravity Control
do
--
-- PX's wind_changer_script (ravander, improved by 0rang3) and
-- gravity_control_script (DabbyB, edited by 0rang3). Both records are one of
-- WA's turn utilities (subtype 19) with an index WA does not use (8), so WA
-- fires them as a utility that does nothing, spending the shot as usual, and
-- the script does the work.
--
-- Wind Changer, on the surrender's slot: while it is selected, 0..9 choose
-- the force; firing it sets the wind to force x 0.0317 towards where the
-- worm faces, through WA's own wind change, so the clouds and the wind bar
-- follow. Gravity Control, on low gravity's slot: 1..5 choose 0.3, 0.5, 1,
-- 1.7 or 2.4 times the match's gravity; firing it holds WA's gravity there
-- until the next turn. Fired with nothing chosen it does not fire (PX gives
-- the shot back).
--
-- Differences: a HUD line says which keys to press and what is chosen, in
-- place of PX's team messages; and PX also puts the gravity back after 10 s
-- with the turn clock stopped, which needs the turn clock (not ported).

local WIND_STEP = 0.0317       -- wind per point of force (PX's), a turn's wind is up to about 0.29
local GRAVITY_FACTORS = { 0.3, 0.5, 1.0, 1.7, 2.4 }
local GRAVITY_NAMES = { "Very Low Gravity", "Low Gravity", "Normal Gravity", "High Gravity", "Very High Gravity" }

local wind_force = 0          -- wf
local gravity_choice          -- TransformedGravity's index, until fired
local gravity_initial         -- InitialGravity: the match's
local gravity_factor          -- ModulatedGravity while Gravity Control is on
local last_digit              -- KeyPressedNow: a digit counts when it goes down

local function world_physics_frame(worm)
  gravity_initial = gravity_initial or wa.world.gravity()
  if not worm.turn then
    return
  end
  local digit = wa.world.keys().digit
  local pressed = digit ~= nil and digit ~= last_digit
  last_digit = digit
  if not pressed then
    return
  end
  if worm.weapon == "surrender" then
    wind_force = digit
    wa.sound.play(worm, 107)
  elseif worm.weapon == "low_gravity" and digit >= 1 and digit <= 5 then
    gravity_choice = digit
    wa.sound.play(worm, 92)
  end
end

wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FRAME_FINISH then
    world_physics_frame(worm)
  elseif msg == wa.msg.FIRE_WEAPON and worm.weapon == "surrender" then
    -- FireFinal(Wind Changer): breeze for none, a calm wind up to 5, strong
    -- above; towards where the worm faces.
    local f = wind_force
    wa.sound.play(worm, f == 0 and "sounds/wind_changer/breeze.wav"
      or f < 6 and "sounds/wind_changer/calm_wind.wav" or "sounds/wind_changer/strong_wind.wav")
    wa.world.set_wind(trunc(f * WIND_STEP * FX) * worm.facing)
  elseif msg == wa.msg.FIRE_WEAPON and worm.weapon == "low_gravity" then
    if not gravity_choice then
      wa.sound.play(worm, "sounds/gravity_control/error.wav")
      return "eat"
    end
    gravity_initial = gravity_initial or wa.world.gravity()
    gravity_factor, gravity_choice = GRAVITY_FACTORS[gravity_choice], nil
    wa.sound.play(worm, "sounds/gravity_control/activate.wav")
    wa.world.set_gravity(trunc(gravity_initial * gravity_factor))
  end
end)

-- Reset when this turn ends; doing it at the next turn start can softlock.
wa.on.turn_end(function()
  if gravity_factor then
    gravity_factor = nil
    wa.world.set_gravity(gravity_initial)
  end
  gravity_choice = nil
end)

if wa.on.hud then
  wa.on.hud(function()
    local worm = current_worm()
    if not worm then
      return
    end
    if worm.weapon == "surrender" then
      wa.hud.line(string.format("Wind Changer: force %d (keys 0-9), then Space", wind_force))
    elseif worm.weapon == "low_gravity" then
      wa.hud.line("Gravity Control: " .. (gravity_choice and GRAVITY_NAMES[gravity_choice]
        or "choose 1-5") .. ", then Space")
    end
  end)
end
end

-- ------------------------------------------------------------------ Jump
do
--
-- PX's jumpscript (utility_jump). Its record throws like a grenade, but
-- nothing leaves the worm: FireFinal gives the worm the shot's own speed --
-- the aim and the charge -- and plays the team's "Jump" line. The worm keeps
-- its aim posture, eyes on the crosshair, until it jumps.
--
-- Differences: PX shows WA's wjump while the charge builds
-- (SetAnimEx(269, FirePower)), which looks ahead rather than along the aim;
-- it also mutes the worm's "Fire!" and "Watch this" lines while the Jump is
-- selected, and stops a fuse and bounce being chosen for it.

-- The first team's "Jump1" speech: WA loads each team's 54 lines in turn
-- after its own sounds, so a worm's is 54 on per team (PX's PlaySoundBank(150)).
local JUMP_SPEECH, SPEECH_LINES = 150, 54

fires.jump = function(fire)
  local worm = fire.worm
  worm:release(fire.vx, fire.vy)
  wa.sound.play(worm, JUMP_SPEECH + SPEECH_LINES * (worm.team - 1))
end
end

-- ------------------------------------------------------------- Laser Gun
--
-- PX's lasergun (CLaserRay). The record is an uzi firing one bullet; PX
-- fires none (FireFinal without super), and each frame sets the worm's shot
-- counters to 0 of 1, so WA keeps the worm in its repeat-fire state, aim
-- live, while a beam burns for 5 s (250 frames) from the worm along its aim.
-- Every fourth frame the beam traces: to the first land, 2048 px at most,
-- cutting 4 px holes there (along the cut when the aim held still); and
-- every worm, mine, crate and oil drum within 5 px of it takes fire damage:
-- a worm 2, then 1 once it has taken 10, and no more after 45 from this beam;
-- an oil drum 4, a crate 1. Drawn: a red strip, its width pulsing from 1.0
-- to 0.5, and glows at the muzzle and where it hits; red sparks from the
-- muzzle, glows rising from the cut, yellow sparks where it touches things.
--
-- Here the engine hands each of WA's shots to on_fire and skips WA's bullet
-- (a gun slot with an on_fire), and the pack holds worm.shots_fired and
-- worm.shots_to_fire as PX does.
--
-- Differences: a mine the beam touches is armed on its fuse, once, rather
-- than sent PX's gun damage (object:hit takes crates and oil drums); the
-- beam's loop sound is played again every 51 frames, not looped.

-- Its own block: the file is at Lua's 200 locals for one chunk.
do
  local LASER_FX = 0x10000
  local LASER_LIFE = 250
  local LASER_REACH = 2048
  local LASER_LOOP_FRAMES = 51 -- laser_loop.wav is 1.02 s
  local LASER_GLOW = "sprites/laser_gun/laser_glow.png"
  local LASER_BEAM = "sprites/laser_gun/laser_beam.png"
  local LASER_DEPTH = 0x10000
  -- States a worm is not firing in: the beam stops (PX keeps it only in
  -- repeat fire, firing, aiming and fired).
  local LASER_STOPS = { standing = true, sliding = true, jetpacking = true, parachuting = true,
    bungee = true, tumbling = true, teleporting = true, drilling = true, punching = true }
  local lasers = {} -- worm id -> the beam

  local function laser_rand(r)
    r.seed = (r.seed * 1103515245 + 12345) % 0x80000000
    return r.seed / 0x80000000
  end

  local function laser_between(r, lo, hi)
    return lo + (hi - lo) * laser_rand(r)
  end

  -- A PX particle: moved, pulled and slowed each game frame, drawn additive.
  local function laser_particle(r, p)
    p.age, p.vx, p.vy = 0, p.vx or 0, p.vy or 0
    r.fx[#r.fx + 1] = p
  end

  -- UpdatePosDir: the beam's direction from the worm's aim (0 down, 1 up)
  -- and side; it starts at the worm and draws from 24 px out.
  local function laser_aim(r, w)
    local ang = (1 - w.aim) * math.pi
    if w.facing < 0 then ang = 2 * math.pi - ang end
    r.dx, r.dy = math.sin(ang), -math.cos(ang)
    r.x = w.x + math.floor((2 * w.facing * r.dy - r.dx) * LASER_FX)
    r.y = w.y + math.floor((-2 - r.dy) * LASER_FX)
    r.gx = r.x + math.floor(24 * r.dx * LASER_FX)
    r.gy = r.y + math.floor(24 * r.dy * LASER_FX)
  end

  local function laser_sparks(r, n, v0, v1, s0, s1)
    local base = (1 - r.aim) * math.pi
    if r.facing < 0 then base = 2 * math.pi - base end
    for _ = 1, n do
      local ang = base + laser_between(r, -0.8, 0.8)
      local v = laser_between(r, v0, v1)
      local s = laser_between(r, s0, s1)
      laser_particle(r, { x = r.gx, y = r.gy, vx = v * math.sin(ang) * LASER_FX,
        vy = -v * math.cos(ang) * LASER_FX, life = 30, drag = 0.3, grav = 0.8,
        s0 = s, s1 = 0.01, c0 = { 255, 0, 0 }, c1 = { 80, 0, 0 } })
    end
  end

  local function laser_objects()
    local out = {}
    for _, group in ipairs({ wa.worms, wa.mines, wa.crates, wa.oil }) do
      if group then
        for _, obj in ipairs(group.all()) do out[#out + 1] = obj end
      end
    end
    return out
  end

  local LASER_RADIUS = { worm = 6, mine = 5, crate = 9, oil = 9 }

  -- PerformTrace with damage: the cut, then everything touching the beam.
  local function laser_trace(r, w)
    local x1 = r.x + math.floor(LASER_REACH * r.dx * LASER_FX)
    local y1 = r.y + math.floor(LASER_REACH * r.dy * LASER_FX)
    local land = wa.land.trace(r.x, r.y, x1, y1)
    local hx, hy = land and land.x or x1, land and land.y or y1
    if land then
      if r.hit and r.dx == r.last_dx and r.dy == r.last_dy then
        -- The aim held: a clean cut from the last hit to this one.
        local steps = math.max(1, math.floor(math.sqrt(((hx - r.hx) / LASER_FX) ^ 2 + ((hy - r.hy) / LASER_FX) ^ 2) / 2))
        for i = 0, steps do
          wa.land.dig({ x = r.hx + (hx - r.hx) * i // steps, y = r.hy + (hy - r.hy) * i // steps, radius = 4 })
        end
      else
        wa.land.dig({ x = hx, y = hy, radius = 4 })
      end
      local s = laser_between(r, 0.6, 0.9)
      laser_particle(r, { x = hx, y = hy, life = 60, drag = 0.2, grav = -0.4, jitter = 0.6,
        s0 = s, s1 = 0.01, c0 = { 255, 0, 0 }, c1 = { 255, 0, 0 } })
      laser_particle(r, { x = hx, y = hy, life = 80, drag = 0, grav = 0,
        s0 = 0.6, s1 = 0.1, c0 = { 200, 0, 0 }, c1 = { 0, 0, 0 } })
    end
    r.hx, r.hy, r.hit = hx, hy, land ~= nil
    local lx, ly = (hx - r.x) / LASER_FX, (hy - r.y) / LASER_FX
    r.draw_beam = lx * lx + ly * ly > 24 * 24
    local length = math.sqrt(lx * lx + ly * ly)
    for _, obj in ipairs(laser_objects()) do
      local ox, oy = (obj.x - r.x) / LASER_FX, (obj.y - r.y) / LASER_FX
      local along = ox * r.dx + oy * r.dy
      local across = math.abs(ox * r.dy - oy * r.dx)
      if along >= 0 and along <= length and across <= 5 + (LASER_RADIUS[obj.kind] or 6)
          and not (obj.kind == "worm" and obj.id == w.id) then
        local key = obj.kind .. ":" .. obj.id
        if obj.kind == "worm" then
          if obj.hp > 0 then
            local taken = r.taken[key] or 0
            local amount = taken >= 45 and 0 or taken >= 10 and 1 or 2
            if amount > 0 then obj:hurt(amount) end
            r.taken[key] = taken + amount
          end
        elseif obj.kind == "oil" or obj.kind == "crate" then
          obj:hit(obj.kind == "oil" and 4 or 1, math.floor(r.dx * LASER_FX), math.floor(r.dy * LASER_FX))
        elseif obj.kind == "mine" and not r.armed[key] then
          r.armed[key] = true
          obj:arm(obj.fuse < 0 and wa.random(1000, 5000) or obj.fuse)
        end
        -- FX_HitObject: a yellow flash and two sparks.
        local px, py = obj.x - math.floor(3 * r.dx * LASER_FX), obj.y - math.floor(3 * r.dy * LASER_FX)
        local tone = math.floor(laser_between(r, 0, 50))
        laser_particle(r, { x = px, y = py, life = 10, drag = 0, grav = 0,
          s0 = laser_between(r, 0.4, 0.8), s1 = 0.01, c0 = { 210, 210 - tone, 0 }, c1 = { 210, 50 - tone, 0 } })
        for _ = 1, 2 do
          local a, v = laser_between(r, 0, 2 * math.pi), laser_between(r, 0.5, 1.8)
          laser_particle(r, { x = px, y = py, vx = v * math.cos(a) * LASER_FX, vy = v * math.sin(a) * LASER_FX,
            life = 30, drag = 0.05, grav = 1, s0 = laser_between(r, 0.2, 0.4), s1 = 0.01,
            c0 = { 255, 255 - tone, 0 }, c1 = { 255, 80 - tone, 0 } })
        end
      end
    end
  end

  local function laser_particles(r)
    for i = #r.fx, 1, -1 do
      local p = r.fx[i]
      p.age = p.age + 1
      if p.age >= p.life then
        table.remove(r.fx, i)
      else
        if p.jitter then
          p.vx = p.vx + math.floor(laser_between(r, -p.jitter, p.jitter) * LASER_FX)
        end
        p.vy = p.vy + math.floor(p.grav * LASER_FX / 10)
        p.vx, p.vy = math.floor(p.vx * (1 - p.drag)), math.floor(p.vy * (1 - p.drag))
        p.x, p.y = p.x + p.vx, p.y + p.vy
      end
    end
  end

  local function laser_stop(r, w)
    r.dead = true
    if w then
      -- WA ends the repeat fire, as when its shots run out.
      w.shots_fired = w.shots_to_fire
      wa.sound.play(w, "sounds/laser_gun/laser_end.wav")
    end
  end

  fires.laser = function(fire)
    local w = fire.worm
    -- Each of WA's shots comes here; one beam per worm, as PX's LaserRayObj.
    if lasers[w.id] then return end
    local r = { worm_id = w.id, life = LASER_LIFE, counter = 0, size = 1.0, first = true,
      taken = {}, armed = {}, fx = {}, seed = (w.x // LASER_FX * 7919 + w.y // LASER_FX) % 0x80000000 }
    r.aim, r.facing = w.aim, w.facing
    laser_aim(r, w)
    r.hx, r.hy, r.last_dx, r.last_dy = r.x, r.y, r.dx, r.dy
    lasers[w.id] = r
    wa.sound.play(w, "sounds/laser_gun/laser_start.wav")
    wa.sound.play(w, "sounds/laser_gun/laser_loop.wav")
    wa.actors.spawn({
      sprite = false, x = w.x, y = w.y, gravity = false, collide = false, owner = w,
      on = function(a)
        r.life = r.life - 1
        laser_particles(r)
        if r.dead then
          if r.life <= -10 and #r.fx == 0 then
            lasers[r.worm_id] = nil
            a:despawn()
          end
          return
        end
        if r.life <= 0 or w.hp <= 0 or not w.turn or w.weapon ~= "uzi" or LASER_STOPS[w.state or ""] then
          laser_stop(r, w.hp > 0 and w or nil)
          return
        end
        w.shots_fired, w.shots_to_fire = 0, 1
        r.size = r.size - 0.07
        if r.size < 0.5 then r.size = 1.0 end
        r.aim, r.facing = w.aim, w.facing
        laser_aim(r, w)
        if r.first then
          r.first = false
          laser_sparks(r, 8, 5, 9, 0.4, 0.7) -- FX_InitialBurst
        end
        if (LASER_LIFE - r.life) % LASER_LOOP_FRAMES == 0 then
          wa.sound.play(w, "sounds/laser_gun/laser_loop.wav")
        end
        if r.counter <= 0 then
          r.counter = 3
          laser_trace(r, w)
          laser_sparks(r, 1, 2, 5, 0.2, 0.5) -- FX_MuzzleSparks
        else
          r.counter = r.counter - 1
        end
        r.last_dx, r.last_dy = r.dx, r.dy
      end,
    })
  end

  if wa.on.draw and wa.draw.ribbon then
    local function red(a, rgb)
      return (math.floor(math.max(0, math.min(255, a))) << 24)
        | (math.floor(rgb[1]) << 16) | (math.floor(rgb[2]) << 8) | math.floor(rgb[3])
    end
    local function laser_glow(x, y, px, color)
      local h = px * LASER_FX / 2
      wa.draw.quad({ sprite = LASER_GLOW, blend = "add", color = color, depth = LASER_DEPTH,
        points = { { x - h, y - h }, { x + h, y - h }, { x + h, y + h }, { x - h, y + h } } })
    end
    wa.on.draw(function()
      for _, r in pairs(lasers) do
        for _, p in ipairs(r.fx) do
          local t = p.age / p.life
          local c = { p.c0[1] + (p.c1[1] - p.c0[1]) * t, p.c0[2] + (p.c1[2] - p.c0[2]) * t,
            p.c0[3] + (p.c1[3] - p.c0[3]) * t }
          laser_glow(p.x, p.y, 32 * (p.s0 + (p.s1 - p.s0) * t), red(255, c))
        end
        if not r.dead then
          local c = red(255, { 255, 0, 0 })
          laser_glow(r.gx, r.gy, 32 * 0.5 * r.size, c)
          if r.draw_beam then
            wa.draw.ribbon({ sprite = LASER_BEAM, blend = "add", depth = LASER_DEPTH, points = {
              { x = r.gx, y = r.gy, width = 2 * 8 * r.size, u = 0, color = c },
              { x = r.hx, y = r.hy, width = 2 * 8 * r.size, u = 1, color = c },
            } })
          end
          if r.hit then laser_glow(r.hx, r.hy, 32 * 0.75 * r.size, c) end
        end
      end
    end)
  end
end

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
-- whatever ammo the scheme gives them, except the Hot Air Balloon and the
-- Wind Changer, which start_turn sets to 3 and 1.

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
local dead_hands = {}
local revived_by_lightning = {}

-- The current Highlander port moves a dead worm's hand to the active worm.
-- A grave revived by Lightning also gets that original hand back. This is a
-- copy: the active worm keeps the weapons it already stole.
restore_lightning_inventory = function(worm)
  local hand = dead_hands[worm.id]
  if not hand then return end
  arsenal:clear(worm)
  for _, weapon in ipairs(hand) do arsenal:add(worm, weapon, 1) end
  dealt[worm.id] = true
  dead_hands[worm.id] = nil
end

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
  -- GiveWeapons: three Hot Air Balloons and a Wind Changer for the turn,
  -- whatever is left.
  worm:ammo("bungee", { set = 3 })
  worm:ammo("surrender", { set = 1 })
end

local function on_death(event)
  local victim = event.victim
  local active = event.active
  revived_by_lightning[victim.id] = nil
  local mine = arsenal:list(victim)
  dead_hands[victim.id] = mine

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

-- --------------------------------------------------------------- Super Tele
do
-- PX's FireFinal arms the teleport, the next M_FRAME starts its pose and
-- sound, and M_FRAME moves the worm 50 frames after that. Keep the click
-- from WA's fire context: the live pointer
-- may have moved by the time the worm arrives. Mask 4 is approximated by
-- three overlapping round cuts, centred where PX places them.
fires.teleports = {} -- worm id -> frozen target and elapsed frames

fires.super_tele_click = function(ev)
  local worm = ev.worm
  if worm.hp <= 0 then return end
  local y = ev.y
  if wa.world.cavern() and y < 19 * 0x10000 then y = 19 * 0x10000 end
  local previous = fires.teleports[worm.id]
  if previous and previous.marker then previous.marker:despawn() end
  -- FireWeapon clears WA's planted X for click-only weapons. Keep a fixed
  -- stock planted-X marker at the saved target until the worm arrives instead.
  local marker = wa.actors.spawn({
    owner = worm, x = ev.x, y = y, sprite = "markerr",
    gravity = false, collide = false, drown = false, loop = true,
  })
  fires.teleports[worm.id] = { x = ev.x, y = y, frames = 0, pending = true, marker = marker }
  wa.sound.play(worm, 68, 0) -- PX's M_SETTARGET confirmation
end

wa.on.worm_message(function(worm, msg)
  if msg ~= wa.msg.FRAME_FINISH then return end
  local tele = fires.teleports[worm.id]
  if not tele then return end
  if worm.hp <= 0 then
    tele.marker:despawn()
    fires.teleports[worm.id] = nil
    return
  end
  if tele.pending then
    tele.pending = false
    -- WA's teleport setup clears its activity flag. Do this after the
    -- Lua-handled FireWeapon return restores that flag, as PX's M_FRAME does.
    worm:set_state("teleporting")
    wa.sound.play(worm, 67, 0) -- PX's teleport start
    return
  end
  tele.frames = tele.frames + 1
  if tele.frames < 50 then return end
  tele.marker:despawn()
  fires.teleports[worm.id] = nil
  worm.x, worm.y = tele.x, tele.y
  for _, rise in ipairs({ 0, 10, 22 }) do
    wa.land.dig({ x = tele.x, y = tele.y - rise * 0x10000, radius = 12 })
  end
end)
end

-- --------------------------------------------------------- electrical weapons
do
-- PX's lightningstrike.txt and tazer.txt share these target classes and beam
-- textures. Only gameplay advances in the actor brains. Drawing below may run
-- at any frame rate and consumes only wa.draw.random(), never WA's sim RNG.
local EP = 0x10000
local ELECTRIC_DEPTH = 0x00190000 -- behind WA terrain, in the GPU occlusion mask
local BEAM = "sprites/lightning/beam.png"
local GLOW = "sprites/lightning/glow.png"
local CLOUD = "sprites/lightning/cloud.png" -- a puff made for the pack, in place of WA's cloudl
local CLOUD_DEPTH = ELECTRIC_DEPTH - 0x1000  -- in front of the beam's top, behind the terrain
local GRENADE_BURST = "sprites/electric_grenade/explosion"
local strikes, arcs, tazed = {}, {}, {}

local function effect_actor(x, y, owner, frame)
  return wa.actors.spawn({
    sprite = GLOW, visible = false, gravity = false, collide = false,
    owner = owner, x = x, y = y, on = frame,
  })
end

local function electrical_targets(graves)
  local out = {}
  for _, group in ipairs({ wa.worms, wa.mines, wa.crates, wa.oil }) do
    for _, obj in ipairs(group.all()) do out[#out + 1] = obj end
  end
  if graves and wa.graves then
    for _, obj in ipairs(wa.graves.all()) do out[#out + 1] = obj end
  end
  return out
end

local function target_radius(obj)
  if obj.kind == "worm" then return 6 end
  if obj.kind == "grave" then return 8 end
  if obj.kind == "mine" then return 5 end
  return 9
end

-- A ray against terrain and the objects PX's collision mask names. Projection
-- is done in world pixels; the chosen endpoint is converted back to 16.16.
-- Equal-distance objects retain the engine's entity traversal order.
local function electrical_trace(x0, y0, dx, dy)
  local far = 10000
  if wa.world.electrical_trace then
    return wa.world.electrical_trace(math.floor(x0), math.floor(y0),
      math.floor(x0 + dx * far * EP), math.floor(y0 + dy * far * EP))
  end
  local land = wa.land.trace(math.floor(x0), math.floor(y0),
    math.floor(x0 + dx * far * EP), math.floor(y0 + dy * far * EP))
  local best = land and math.sqrt(((land.x - x0) / EP) ^ 2 + ((land.y - y0) / EP) ^ 2) or far
  local hit = land and { x = land.x, y = land.y, obj = nil } or nil
  for _, obj in ipairs(electrical_targets(true)) do
    local ox, oy = (obj.x - x0) / EP, (obj.y - y0) / EP
    local along = ox * dx + oy * dy
    local across = math.abs(ox * dy - oy * dx)
    if along > 0 and along < best and across <= target_radius(obj) then
      best = along
      hit = { x = obj.x, y = obj.y, obj = obj }
    end
  end
  return hit
end

local function strike_hit(s)
  if not s.hit then return end
  local radius2 = (6 * EP) ^ 2
  local targets = wa.world.electrical_nearby
    and wa.world.electrical_nearby(s.ex, s.ey, 24, true) or electrical_targets(true)
  for _, obj in ipairs(targets) do
    local dx, dy = obj.x - s.ex, obj.y - s.ey
    local r = (target_radius(obj) + 6) * EP
    if dx * dx + dy * dy <= math.max(radius2, r * r) then
      if obj.kind == "worm" then
        if not revived_by_lightning[obj.id] then obj:heal(25) end
      elseif obj.kind == "grave" then
        if obj.worm_id ~= 0 then
          local id = obj.worm_id
          local worm = obj:revive(id, 10)
          if worm then
            revived_by_lightning[worm.id] = true
            restore_lightning_inventory(worm)
          end
        end
      elseif obj.kind == "mine" then
        obj:arm(obj.fuse < 0 and wa.random(1000, 5000) or obj.fuse)
      elseif obj.kind == "crate" or obj.kind == "oil" then
        obj:hit(100, 0, 0)
      end
    end
  end
end

-- PX's cloud: every second frame of the strike's life a puff of WA's large
-- cloud, tinted a dark bluish grey, is thrown out from the top of the beam
-- and slowed by the air; a core puff (100 frames, 1.2x to 0.6x) until the
-- strike is spent, a surrounding one (140 frames, 1x to nothing) until the
-- strike is gone. Each fades in from nothing. Also PX's sparks: while the
-- beam holds, a glow thrown from where it hit, falling. Both are advanced
-- here, once per game frame, from the strike's own generator, and only drawn
-- below; nothing else reads them.
local function strike_rand(s)
  s.seed = (s.seed * 1103515245 + 12345) % 0x80000000
  return s.seed / 0x80000000
end

local function strike_puff(s, life, drag, s0, s1)
  local xvel = strike_rand(s) * 2 - 1
  local yvel = 1 - xvel * xvel
  s.cloud[#s.cloud + 1] = { x = s.sx, y = s.sy, vx = 16 * xvel * EP,
    vy = (strike_rand(s) * 9 - 8) * yvel * EP, drag = drag, age = 0, life = life, s0 = s0, s1 = s1 }
end

local function strike_particles(s)
  if s.tail > 0 then
    s.cloud_timer = s.cloud_timer - 1
    if s.cloud_timer <= 0 then
      if s.life > 0 then strike_puff(s, 100, 0.3, 1.2, 0.6) end
      strike_puff(s, 140, 0.15, 1.0, 0.01)
      s.cloud_timer = 2
    end
    if s.delay == 0 and s.life > 0 and s.hit then
      local a = strike_rand(s) * 2 * math.pi
      local v = (1 + strike_rand(s) * 2) * EP
      s.sparks[#s.sparks + 1] = { x = s.ex, y = s.ey, vx = math.cos(a) * v, vy = math.sin(a) * v, age = 0 }
    end
  end
  for i = #s.cloud, 1, -1 do
    local p = s.cloud[i]
    p.age = p.age + 1
    if p.age >= p.life then
      table.remove(s.cloud, i)
    else
      p.x, p.y = p.x + p.vx, p.y + p.vy
      p.vx, p.vy = p.vx * (1 - p.drag), p.vy * (1 - p.drag)
    end
  end
  for i = #s.sparks, 1, -1 do
    local p = s.sparks[i]
    p.age = p.age + 1
    if p.age >= 50 then
      table.remove(s.sparks, i)
    else
      p.x, p.y, p.vy = p.x + p.vx, p.y + p.vy, p.vy + EP // 8
    end
  end
end

lightning_click = function(ev)
  local dirx = 0.5 * ev.worm.facing
  local diry = math.sqrt(3) / 2
  local sy = -270 * EP
  local sx = math.floor(ev.x - ((ev.y - sy) / EP) * dirx / diry * EP)
  local hit = electrical_trace(sx, sy, dirx, diry)
  local ex, ey = hit and hit.x or sx + math.floor(300 * dirx * EP),
    hit and hit.y or sy + math.floor(300 * diry * EP)
  local distance = math.sqrt(((ex - sx) / EP) ^ 2 + ((ey - sy) / EP) ^ 2)
  if hit and distance > 300 then
    sx, sy = ex - math.floor(300 * dirx * EP), ey - math.floor(300 * diry * EP)
  end
  local s = { sx = sx, sy = sy, ex = ex, ey = ey, hit = hit, dirx = dirx, diry = diry,
    delay = 150, life = 16, tail = 60, owner = ev.worm, ticks = 0,
    seed = (ex // EP * 7919 + ey // EP) % 0x80000000, cloud_timer = 0, cloud = {}, sparks = {} }
  strikes[#strikes + 1] = s
  wa.sound.play(ev.worm, "sounds/lightning/thunder.wav")
  effect_actor(ex, ey, ev.worm, function(a)
    s.ticks = s.ticks + 1
    strike_particles(s)
    if s.delay > 0 then
      s.delay = s.delay - 1
      if s.delay == 0 then wa.sound.play(a, "sounds/lightning/hit.wav") end
    elseif s.life > 0 then
      s.life = s.life - 1
      if s.life == 0 then strike_hit(s) end
    elseif s.tail > 0 then
      s.tail = s.tail - 1
    elseif #s.cloud == 0 and #s.sparks == 0 then
      for i, held in ipairs(strikes) do
        if held == s then table.remove(strikes, i); break end
      end
      a:despawn()
    end
  end)
end

local function target_key(obj)
  return obj.kind .. ":" .. obj.id
end

local function find_target(key)
  for _, obj in ipairs(electrical_targets(false)) do
    if target_key(obj) == key then return obj end
  end
end

local function closest_target(arc)
  local best, distance = nil, (200 * EP) ^ 2
  local targets = wa.world.electrical_nearby
    and wa.world.electrical_nearby(arc.x, arc.y, 200, false) or electrical_targets(false)
  for _, obj in ipairs(targets) do
    local key = target_key(obj)
    if not arc.ignore[key] and (obj.kind ~= "worm" or obj.hp > 0) then
      local dx, dy = obj.x - arc.x, obj.y - arc.y
      local d = dx * dx + dy * dy
      if d < distance then best, distance = obj, d end
    end
  end
  return best, distance
end

local function release_taze(key)
  local hold = tazed[key]
  if not hold then return end
  hold.count = hold.count - 1
  if hold.count > 0 then return end
  local worm = find_target(key)
  if worm then
    -- Knocked flying meanwhile, the engine has already let it go.
    if worm.taken then worm:release(0, 0) end
    worm.body_visible = true
  end
  tazed[key] = nil
end

-- A tazed worm is the pack's (worm:take): the engine eats its moves and
-- jumps; it cannot start a shot either.
wa.on.worm_message(function(worm, msg)
  if msg == wa.msg.FIRE_WEAPON and tazed[target_key(worm)] then
    return "eat"
  end
end)

local function zap_target(arc, pending)
  local obj = find_target(pending.key)
  release_taze(pending.key)
  if not obj then return end
  if obj.kind == "worm" then
    obj:hurt(24)
    obj.vx, obj.vy = pending.side * 1.2 * EP, -4 * EP
  elseif obj.kind == "mine" then
    obj:arm(400)
  elseif obj.kind == "crate" or obj.kind == "oil" then
    obj:hit(12, pending.side * 1.2 * EP, -4 * EP)
  end
end

local function progress_arc(arc)
  arc.explosion = arc.explosion + 1
  for i = #arc.pending, 1, -1 do
    local p = arc.pending[i]
    p.time = p.time - 1
    if p.time <= 0 then
      zap_target(arc, p)
      table.remove(arc.pending, i)
    end
  end
  if arc.pause > 0 then arc.pause = arc.pause - 1; return end
  if arc.life <= 0 then
    if #arc.points > 0 then table.remove(arc.points, 1) end
    return
  end
  arc.life = arc.life - 1
  local target, distance = closest_target(arc)
  if target then
    local dx, dy = target.x - arc.x, target.y - arc.y
    local d = math.sqrt(distance)
    if d <= 10 * EP then
      local key = target_key(target)
      arc.ignore[key] = true
      arc.pending[#arc.pending + 1] = { key = key, side = dx < 0 and -1 or 1, time = 24 }
      if target.kind == "worm" then
        if tazed[key] then
          tazed[key].count = tazed[key].count + 1
        else
          tazed[key] = { x = target.x, y = target.y, count = 1,
            sheet = wa.random(1, 2) == 1 and "sprites/electric_grenade/tazed1" or "sprites/electric_grenade/tazed2" }
        end
        target.body_visible = false
        -- Held where it stands, the turn stopped, until the zap.
        target:take{ turn = "freeze" }
      end
      arc.x, arc.y = target.x, target.y
      arc.life = 20
      arc.pause = 14
      for i = #arc.points, 2, -1 do table.remove(arc.points, i) end
      arc.points[#arc.points + 1] = { arc.x, arc.y }
      return
    end
    local pull = math.min(1, math.sqrt(10 * EP / d))
    arc.dx = arc.dx + ((dx / d) - arc.dx) * pull
    arc.dy = arc.dy + ((dy / d) - arc.dy) * pull
  else
    arc.dx = arc.dx + wa.random(-100, 100) / 100
    arc.dy = arc.dy + wa.random(-100, 100) / 100
  end
  local norm = math.sqrt(arc.dx * arc.dx + arc.dy * arc.dy)
  if norm < 0.01 then arc.dx, arc.dy = 0, -1 else arc.dx, arc.dy = arc.dx / norm, arc.dy / norm end
  local nx, ny = arc.x + arc.dx * 20 * EP, arc.y + arc.dy * 20 * EP
  local land = wa.land.trace(math.floor(arc.x), math.floor(arc.y), math.floor(nx), math.floor(ny))
  if land then
    if land.starts_solid then arc.life = 0; return end
    -- Follow the tangent that moves closer to the target, as PX's arc does.
    local tx, ty = land.tx or 1, land.ty or 0
    if target then
      local a = (target.x - (land.x + tx * 10 * EP)) ^ 2 + (target.y - (land.y + ty * 10 * EP)) ^ 2
      local b = (target.x - (land.x - tx * 10 * EP)) ^ 2 + (target.y - (land.y - ty * 10 * EP)) ^ 2
      if b < a then tx, ty = -tx, -ty end
    end
    arc.dx, arc.dy = tx, ty
    arc.x, arc.y = land.x + (land.nx or 0) * 10 * EP + tx * 10 * EP,
      land.y + (land.ny or -1) * 10 * EP + ty * 10 * EP
  else
    arc.x, arc.y = arc.x + arc.dx * 10 * EP, arc.y + arc.dy * 10 * EP
  end
  arc.points[#arc.points + 1] = { arc.x, arc.y }
  if #arc.points > 33 then table.remove(arc.points, 1) end
end

electric_grenade_explode = function(ev)
  local arc = { x = ev.x, y = ev.y, dx = 0, dy = -1, life = 16, pause = 0,
    points = { { ev.x, ev.y } }, ignore = {}, pending = {}, explosion = 0,
    burst_x = ev.x, burst_y = ev.y, sound_age = 0 }
  if ev.worm then arc.ignore[target_key(ev.worm)] = true end
  arcs[#arcs + 1] = arc
  -- An explosion without a worm would leave the driver owned by the exploding
  -- grenade: the turn's worm owns it then, as every other effect's.
  local driver = effect_actor(ev.x, ev.y, ev.worm or current_worm(), function(a)
    arc.sound_age = arc.sound_age + 1
    if arc.life > 0 and arc.sound_age % 46 == 0 then
      wa.sound.play(a, "sounds/lightning/tazer_loop.wav")
    end
    progress_arc(arc)
    if arc.life <= 0 and #arc.points == 0 and #arc.pending == 0 then
      for i, held in ipairs(arcs) do
        if held == arc then table.remove(arcs, i); break end
      end
      a:despawn()
    end
  end)
  wa.sound.play(driver, "sounds/lightning/tazer_loop.wav")
end

if wa.on.draw and wa.draw.ribbon then
  local function colour(a, r, g, b)
    return (math.floor(a) << 24) | (r << 16) | (g << 8) | b
  end
  local function glow(x, y, size, color)
    local h = size * EP / 2
    wa.draw.quad({ sprite = GLOW, blend = "add", color = color, depth = ELECTRIC_DEPTH,
      points = { {x-h,y-h}, {x+h,y-h}, {x+h,y+h}, {x-h,y+h} } })
  end
  -- PX's lightningstrike RenderLightning. Its shape is fractal noise, made
  -- afresh each game frame while the beam holds: each point is the middle of
  -- its two neighbours plus a random nudge, halving the span each pass. A
  -- look, so from wa.draw.random, never WA's generator.
  local LR, LG, LB = 120, 140, 255
  local function lerp(t, a, b) return a + (b - a) * t end
  local function noise_span(noise, off, divs, scale, first, last)
    for i = 0, divs - 1 do noise[off + i] = 0 end
    noise[off], noise[off + divs - 1] = first, last
    local k = divs
    local l = k >> 1
    while l > 0 do
      for i = l, divs - 1 - l, k do
        noise[off + i] = (noise[off + i - l] + noise[off + i + l]) * 0.5 + (wa.draw.random() * 2 - 1) * scale
      end
      k = l
      l = k >> 1
    end
  end
  -- The main beam's 9 points, and 6 branches of 9 at random points on it.
  local function new_shape(s)
    s.noise, s.attach = {}, {}
    noise_span(s.noise, 0, 9, 1.0, 0, 0)
    for _ = 1, 6 do s.attach[1 + math.floor(wa.draw.random() * 8)] = true end
    for i = 0, 5 do
      local off = 2 + wa.draw.random() * 4
      if wa.draw.random() < 0.5 then off = -off end
      noise_span(s.noise, 9 + 9 * i, 9, 0.5, 0, off)
    end
    s.ground = 0.5 + wa.draw.random() * 0.3
    s.shape_tick = s.ticks
  end
  -- PX's RenderBeam: one textured strip through the noise, `width` (a half
  -- width, as PX's) tapering to `endwidth`, and a glow at every point fading
  -- towards the end.
  local function beam(noise, off, divs, width, endwidth, scale, x1, y1, x2, y2, glowalpha)
    if divs < 2 then return end
    local dx, dy = (x2 - x1) / EP, (y2 - y1) / EP
    local dd = math.sqrt(dx * dx + dy * dy)
    if dd <= 0 then return end
    dx, dy = dx / dd, dy / dd
    local pts, d = {}, divs - 1
    for i = 0, divs - 1 do
      local f = i / d
      local n = noise[off + i] or 0
      local x = lerp(f, x1, x2) + scale * dy * n * EP
      local y = lerp(f, y1, y2) - scale * dx * n * EP
      pts[#pts + 1] = { x = x, y = y, width = 2 * lerp(f, width, endwidth), u = f,
        color = colour(255, LR, LG, LB) }
      local a = 255 * glowalpha * (1 - f)
      if a >= 1 then glow(x, y, 64, colour(a, LR, LG, LB)) end
    end
    wa.draw.ribbon({ sprite = BEAM, blend = "add", depth = ELECTRIC_DEPTH, points = pts })
  end
  local function draw_strike(s)
    -- The cloud, dark and alpha-blended over the sky.
    for _, p in ipairs(s.cloud) do
      local t = p.age / p.life
      local size = lerp(t, p.s0, p.s1)
      local hw, hh = 64 * size * EP, 40 * size * EP
      wa.draw.quad({ sprite = CLOUD, blend = "alpha", depth = CLOUD_DEPTH,
        color = colour(255 * t, 45, 40, 60),
        points = { { p.x - hw, p.y - hh }, { p.x + hw, p.y - hh }, { p.x + hw, p.y + hh }, { p.x - hw, p.y + hh } } })
    end
    for _, p in ipairs(s.sparks) do
      local t = p.age / 50
      glow(p.x, p.y, 13 * (1 - t) + 1, colour(255, LR, LG, LB))
    end
    if s.life <= 0 or s.delay >= 8 then return end
    if not s.noise or (s.delay == 0 and s.shape_tick ~= s.ticks) then new_shape(s) end
    -- Before it lands the beam grows down from the cloud over 8 frames.
    local divs, ex, ey = 9, s.ex, s.ey
    if s.delay > 0 then
      local fr = (8 - s.delay) / 8
      divs = math.floor(9 * fr)
      ex, ey = lerp(fr, s.sx, s.ex), lerp(fr, s.sy, s.ey)
    end
    beam(s.noise, 0, divs, 35, 3, 15, s.sx, s.sy, ex, ey, 1.0)
    local sub, d = 0, divs - 1
    for i = 0, divs - 1 do
      if s.attach[i] and d > 0 then
        local f = i / d
        local x = lerp(f, s.sx, ex) + 10 * s.diry * s.noise[i] * EP
        local y = lerp(f, s.sy, ey) - 10 * s.dirx * s.noise[i] * EP
        beam(s.noise, 9 + 9 * sub, 9, lerp(f, 10, 1), 0.1, 15 * (1 - f), x, y,
          x + s.dirx * 100 * (1 - f) * EP, y + s.diry * 100 * (1 - f) * EP, 0.5 * (1 - f))
        sub = sub + 1
      end
    end
    glow(s.sx + 10 * s.dirx * EP, s.sy + 10 * s.diry * EP, 230, colour(255, LR, LG, LB))
    if s.delay == 0 and s.hit then glow(s.ex, s.ey, 128 * s.ground, colour(255, LR, LG, LB)) end
  end
  wa.on.draw(function()
    for _, s in ipairs(strikes) do
      draw_strike(s)
    end
    for _, arc in ipairs(arcs) do
      if arc.explosion < 10 then
        local h = 75 * EP
        wa.draw.quad({ sprite=GRENADE_BURST, frame=arc.explosion,
          blend="add", color=0x551E14EB, depth=ELECTRIC_DEPTH,
          points={{arc.burst_x-h,arc.burst_y-h},{arc.burst_x+h,arc.burst_y-h},
            {arc.burst_x+h,arc.burst_y+h},{arc.burst_x-h,arc.burst_y+h}} })
      end
      if #arc.points >= 2 then
        -- PX's CTazerShot: one strip through the arc's points, thickest in
        -- the middle (9, a half width, as PX's), wobbling up to 10 px across
        -- its path by fractal noise made afresh each game frame, a glow at
        -- every point and a big one at the tip; all fading as the arc dies.
        if arc.shape_tick ~= arc.sound_age then
          arc.noise = {}
          noise_span(arc.noise, 0, 33, 1.0, 0, 0)
          arc.shape_tick = arc.sound_age
        end
        local pts, num = {}, #arc.points - 1
        local fade = math.min(1, arc.life / 6)
        for i = 0, num do
          local t = i / num
          local x, y = arc.points[i + 1][1], arc.points[i + 1][2]
          if i > 0 and i < num then
            local px, py = arc.points[i][1], arc.points[i][2]
            local nx, ny = (y - py) / EP, (px - x) / EP
            local d = math.sqrt(nx * nx + ny * ny)
            if d > 0 then
              local n = 10 * (arc.noise[i - 1] or 0) / d * EP
              x, y = x + n * nx, y + n * ny
            end
          end
          local f = math.min(1, 4 * t * (1 - t) + 0.1)
          local f2 = f * fade
          local c = colour(255, math.floor(80 * f2), math.floor(100 * f2), math.floor(255 * f2))
          pts[i + 1] = { x = x, y = y, width = 2 * 9 * f, u = t, color = c }
          glow(x, y, i == num - 1 and 115 or 38, c)
        end
        wa.draw.ribbon({ sprite = BEAM, blend = "add", depth = ELECTRIC_DEPTH, points = pts })
      end
    end
    for key, hold in pairs(tazed) do
      local worm = find_target(key)
      if worm then
        local x, y = worm.x, worm.y
        local h = 30 * EP
        wa.draw.quad({ sprite=hold.sheet, frame=math.floor(wa.draw.random()*4), blend="alpha", depth=ELECTRIC_DEPTH,
          points={{x-h,y-h},{x+h,y-h},{x+h,y+h},{x-h,y+h}} })
        -- PX's tazed worm: a glow 0.4 to 0.7 of the sheet, flickering.
        glow(x, y, 128 * (0.4 + 0.3 * wa.draw.random()), colour(255, 80, 100, 255))
      end
    end
  end)
end
end

-- ---------------------------------------------------------------- Javelin

do
  local speed = {}
  -- Pre keeps the incoming speed even when this frame's stock collision
  -- destroys the missile. Post keeps acceleration for the following frame.
  wa.on.missile_frame(function(m)
    if m.weapon == "prod" then speed[m.id] = { m.vx, m.vy } end
  end)

  local function trunc(n) return n < 0 and math.ceil(n) or math.floor(n) end
  local function orientation(vx, vy)
    if vx == 0 then return vy > 0 and 16 or 0 end
    if vy == 0 then return vx > 0 and 8 or 24 end
    -- PX uses ratio bins, not evenly spaced atan2 angles.
    if vx > 0 and vy < 0 then return math.min(trunc(3 * vx / -vy), 7) end
    if vx > 0 then return math.min(trunc(8 + 3 * vy / vx), 15) end
    if vy > 0 then return math.min(trunc(16 + 3 * -vx / vy), 23) end
    return math.min(trunc(24 + 3 * -vy / -vx), 31)
  end
  local function within(o, x, y, r)
    return o and math.abs(x - o.x) < r * 0x10000 and math.abs(y - o.y) < r * 0x10000
  end
  fires.javelin = function(ev)
    local v = ev.missile and speed[ev.missile]
    if ev.missile then speed[ev.missile] = nil end
    local vx, vy = v and v[1] or 0, v and v[2] or 0
    local target
    -- The circle encloses PX's strict 20px square. Keep native traversal
    -- order, including the shooter; PX stops at the first eligible object.
    for _, o in ipairs(wa.world.electrical_nearby(ev.x, ev.y, 29, false)) do
      if (o.kind == "worm" or o.kind == "mine" or o.kind == "crate" or o.kind == "oil")
        and within(o, ev.x, ev.y, 20) then target = o; break end
    end
    if not target then
      local active = current_worm()
      if within(active, ev.x, ev.y, 25) then target = active end
    end
    if target then
      target.vx, target.vy = trunc(vx / 4), trunc(vy / 4)
      if target.kind == "worm" then target:hurt(20)
      else target:hit(20, trunc(vx / 2), trunc(vy / 2), "projectile") end
      return
    end
    wa.land.stamp{ sprite = "sprites/javelin/stamp", frame = orientation(vx, vy), x = ev.x, y = ev.y }
    -- PX plays it unplaced. On the turn's worm: an explosion's ev.worm is the
    -- missile's owner, which need not be a worm and has no sound of its own.
    local shooter = current_worm()
    if shooter then wa.sound.play(shooter, "sounds/javelin_impact.wav") end
  end
end
