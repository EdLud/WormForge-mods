-- Chaos skin: retarget stock body / cluster sprites across claimed slots.
-- No worm_sprites / aim poses. Multi-sheet leftovers stay stock on purpose.
--
-- Shuffle runs on the first worm_message (same window Highlander deals), via
-- wa.random on the live match RNG — not at InitGraphic.
--
-- Flight rewrite only touches banks that already had a sprite (plus primary
-- render/weapon). Empty sheep/HM mode-switch banks stay 0 so behaviour is
-- unchanged; only the look changes.

local POOL = {
  "missile", "mortar", "grenade", "banana", "hgrenade", "cluster", "clustlet",
  "petrolbm", "mbbomb", "arrow", "bullet", "dynamite", "mineon", "mineoff",
  "sheepwlk", "sheepfal", "sheepbrn", "sheeplau", "spsheep1", "spsheep2",
  "aquashp1", "aquashp2", "cowwalk", "cowjump", "skunk1", "skunk2", "sally",
  "donkey", "pigeonr0", "hmissil1", "hmissil2", "molewalk", "moledig1",
  "drill", "fireball", "phone", "cdrom", "tamborin", "meteor", "carpet1",
  "airmisl", "letter1", "oildrum", "targets", "donor",
}

local CLUSTER = {
  cluster_bomb = true,
  banana_bomb = true,
  super_banana = true,
  ming_vase = true,
  mortar = true,
}

local WEAPONS = {
  "bazooka", "homing_missile", "mortar", "homing_pigeon", "sheep_launcher",
  "grenade", "cluster_bomb", "banana_bomb", "dynamite", "mine", "sheep",
  "super_sheep", "aqua_sheep", "mole_bomb", "holy_grenade", "petrol_bomb",
  "mb_bomb", "skunk", "ming_vase", "mad_cow", "old_woman", "donkey",
  "super_banana", "salvation_army", "magic_bullet", "longbow",
}

for _, weapon in ipairs(WEAPONS) do
  wa.weapons.replace({ weapon = weapon })
end

local function pick()
  return POOL[wa.random(1, #POOL)]
end

local shuffled = false
local function reshuffle()
  if shuffled then
    return
  end
  shuffled = true
  for _, weapon in ipairs(WEAPONS) do
    local body = pick()
    local spec = { weapon = weapon, sprite = body }
    if CLUSTER[weapon] then
      spec.cluster = pick()
    end
    wa.weapons.retarget(spec)
    local bit = spec.cluster and (" cluster=" .. spec.cluster) or ""
    wa.log(string.format("random_sprites %s -> %s%s", weapon, body, bit))
  end
  wa.log(string.format("random_sprites reshuffled %d slots via wa.random", #WEAPONS))
end

wa.on.worm_message(function()
  reshuffle()
end)
