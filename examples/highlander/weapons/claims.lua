-- Highlander: the slot claims. Split from rules.lua by tools/split_highlander.py.
local shared = require("lib/shared")
local PORTED = shared.PORTED
local PX_ART = shared.PX_ART
local PX_HOLDS = shared.PX_HOLDS
local WEP_NAME = shared.WEP_NAME
local WEP_PATCH = shared.WEP_PATCH

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
