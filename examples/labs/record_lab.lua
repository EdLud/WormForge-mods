-- Record Lab: WA's Bazooka with one field of its weapon record changed, one
-- weapon per field, to settle what the field does before it gets a name in
-- the Lua API (docs/weapon-data-tables-proposal.md, "Field audit"). Fire
-- each beside WA's own Bazooka and compare; the HUD names the field and what
-- each reading would show, and every hurt is logged to wkLua.log.
--
-- The fields are written raw (`patch = { [offset] = value }`, the entry's
-- absolute offset), so nothing here depends on the names under test.

local LABS = {
  ["labs.rec_push"] = { field = 0x50, value = 0,
    a = "push power: no knockback, damage as usual",
    b = "damage: no damage" },
  ["labs.rec_damage"] = { field = 0x54, value = 100,
    a = "damage: 100 at the centre, a bigger crater",
    b = "blast radius only" },
  ["labs.rec_70"] = { field = 0x70, value = 0,
    a = "gravity: flies straight",
    b = "trail speed: the smoke trail changes" },
  ["labs.rec_84"] = { field = 0x84, value = 300,
    a = "gravity: drops three times as fast",
    b = "friction: no change in flight" },
  ["labs.rec_7c"] = { field = 0x7C, value = 0,
    a = "wind on/off: ignores the wind (try with wind)",
    b = "explosion response: other blasts no longer push it" },
  ["labs.rec_64"] = { field = 0x64, value = 1,
    a = "impact: bounces like a grenade, explodes on its fuse",
    b = "animation type: spins, still explodes on contact" },
  ["labs.rec_44"] = { field = 0x44, value = 1,
    a = "grenade style: bounces, takes the fuse you set",
    b = "PX's runAway: no visible change" },
  ["labs.rec_48"] = { field = 0x48, value = 0,
    a = "collision mask: flies through worms",
    b = "collision radius: hits as usual" },
  ["labs.rec_90"] = { field = 0x90, value = 0x10042,
    a = "flight sound: hisses (WA's Fuse) in flight",
    b = "alt sprite: a different shell" },
  ["labs.rec_68"] = { field = 0x68, value = 0,
    a = "trail sprite: no smoke trail",
    b = "flight flags: something else changes" },
}

local shared_installed = false

-- The HUD line and the hurt log, once for all lab weapons.
local function install_shared()
  if shared_installed then return end
  shared_installed = true
  wa.on.hurt(function(hit)
    if hit.phase == "post" and hit.lost > 0 then
      wa.log(("record lab: %s -%d hp"):format(hit.kind, hit.lost))
    end
  end)
  wa.on.hud(function()
    local worm
    for _, w in ipairs(wa.worms.all()) do
      if w.turn then worm = w break end
    end
    local lab = worm and LABS[worm.weapon]
    if lab then
      wa.hud.line(("Record lab: +0x%X = %d"):format(lab.field, lab.value), 14, 40)
      wa.hud.line("  if " .. lab.a, 14, 56)
      wa.hud.line("  if " .. lab.b, 14, 72)
    end
  end)
end

return {
  defaults = { ammo = { round_start = -1 }, delay = 0 },
  install = function(ctx)
    local lab = LABS[ctx.id]
    install_shared()
    wa.weapons.replace({
      copy_from = "stock.bazooka",
      name = ("Lab +0x%X"):format(lab.field),
      patch = { [lab.field] = lab.value },
      on_explode = function(ev)
        wa.log(("record lab: +0x%X = %d exploded at %d,%d"):format(lab.field, lab.value, ev.x // 1, ev.y // 1))
      end,
    })
  end,
}
