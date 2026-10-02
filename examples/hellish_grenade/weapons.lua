-- Project X's Hellish Hand-Grenade, on the Holy Hand Grenade's slot.
--
-- How it fires: copy_from the stock Holy Hand Grenade, then named patch for
-- the PX hellish.wep diffs (web editor style). Against stock it has a weaker
-- blast (70 damage, 80 power, not 100/100), bursts into fire on detonation
-- as the Petrol Bomb does, and the rest -- fixed 3 s fuse, bounce, gravity,
-- spin -- stays the Holy Grenade's.
--
-- PX's script only draws it: the worm holds the horned grenade, and the
-- thrown grenade spins with it.
--
-- The art is PX's pre-baked set from weapon_hellish_hand_grenade, split from
-- its vertical strips into frame folders:
--   aim, aimu, aimd     the worm holding it, 32 aim angles, flat/up/down
--   draw, drawu, drawd  the worm taking it out, 10 frames, flat/up/down
--   grenade             the thrown grenade, 32 spin frames
-- The icon is PX's hhh_ico.png byte for byte, so replays share its asset.
wa.weapons.replace({
  weapon = "holy_grenade",
  copy_from = "holy_grenade",
  name = "Hellish Hand-Grenade",
  patch = {
    damage = 70,
    blast = 80,
    glow_sprite = 154,
    homing_sprite = 161,
    detonation = 2,
    cluster_count = 150,
    cluster_speed = 70,
    cluster_power = 1000,
    cluster_angle = 1,
  },
  panel_icon = "sprites/hhh_ico.png",
  sprite = "sprites/grenade",
  worm_sprites = {
    weaponlnk = "sprites/aim", weaponlnku = "sprites/aimu", weaponlnkd = "sprites/aimd",
    wthrow = "sprites/draw", wthrowu = "sprites/drawu", wthrowd = "sprites/drawd",
  },
})
