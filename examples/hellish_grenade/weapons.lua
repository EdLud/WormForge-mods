-- Project X's Hellish Hand-Grenade, on the Holy Hand Grenade's slot.
--
-- How it fires comes from PX's own weapon file, hellish.wep, copied byte for
-- byte from weapon_hellish_hand_grenade: WA's weapon table entry behind a PX
-- tag (weapons::wep). Against the stock Holy Hand Grenade it has a weaker
-- blast (70 damage, 80 power, not 100/100), bursts into fire on detonation
-- as the Petrol Bomb does, gives a 3 s retreat, and swaps the Hallelujah and
-- its bounce for two of the team's voice lines. The rest -- the fixed 3 s
-- fuse, bounce, gravity, spin -- is the Holy Grenade's.
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
  wep = "hellish.wep",
  name = "Hellish Hand-Grenade",
  panel_icon = "sprites/hhh_ico.png",
  sprite = "sprites/grenade",
  worm_sprites = {
    weaponlnk = "sprites/aim", weaponlnku = "sprites/aimu", weaponlnkd = "sprites/aimd",
    wthrow = "sprites/draw", wthrowu = "sprites/drawu", wthrowd = "sprites/drawd",
  },
})
