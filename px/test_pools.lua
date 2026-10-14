-- Highlander rules as the hl.rules add-on: its pools come from each placed
-- weapon's settings, in slot order. From the repo root:
-- lua mods/px/test_pools.lua
local root = HIGHLANDER_ROOT or "mods/px/"
package.path = root .. "?.lua;" .. package.path
local logs, hooks, dealt_from = {}, {}, {}
local cavern = false
wa = {
  log = function(s) logs[#logs + 1] = s end,
  msg = setmetatable({}, { __index = function(_, k) return k end }),
  on = setmetatable({}, { __index = function(_, name) return function(f) hooks[name] = f end end }),
  world = { cavern = function() return cavern end },
  inventory = {
    create = function(spec)
      local inv = { slots = spec.slots }
      function inv:deal(_, pool) dealt_from[#dealt_from + 1] = table.concat(pool, ",") end
      function inv:list() return {} end
      return inv
    end,
  },
}

local function check(what, ok, detail)
  print((ok and "  ok   " or "  FAIL ") .. what .. (detail and ("   [" .. detail .. "]") or ""))
  if not ok then error(what, 2) end
end

-- A small set, not PX's: two offensive (one kept off cavern maps), one
-- second, one movement, one not dealt; in slot order, as ctx.placed is.
local function w(id, slot, pool, cave) return { id = id, stock_slot = slot, options = { pool = pool, cavern = cave } } end
local placed = {
  w("px.double_bazooka", "grenade", "offensive", true),
  w("stock.shotgun", "shotgun", "second", true),
  w("stock.mine_strike", "mine_strike", "offensive", false),
  w("px.jump", "ninja_rope", "movement", true),
  w("stock.skip_go", "skip_go", "not dealt", true),
}
local weapons = {}
for _, p in ipairs(placed) do weapons[p.id] = { stock_slot = p.stock_slot } end
local rules = dofile(root .. "components/highlander.lua")
rules.install({ weapons = weapons, placed = placed })
local shared = require("lib/shared")
local P = shared.POOLS
print("pools: from each placed weapon's settings")
check("offensive, in slot order", table.concat(P.offensive, ",") == "grenade,mine_strike", table.concat(P.offensive, ","))
check("off cavern maps by its own setting", table.concat(P.cave_offensive, ",") == "grenade")
check("second and movement", P.second[1] == "shotgun" and P.movement[1] == "ninja_rope")
check("not dealt is in no pool", table.concat(shared.POOLED, ",") == "grenade,mine_strike,shotgun,ninja_rope",
  table.concat(shared.POOLED, ","))

print("deal: one from each pool")
hooks.worm_message({ id = 17 }, "FRAME_FINISH")
check("open map", table.concat(dealt_from, " | ") == "grenade,mine_strike | shotgun | ninja_rope", table.concat(dealt_from, " | "))
dealt_from, cavern = {}, true
hooks.worm_message({ id = 18 }, "FRAME_FINISH")
check("cavern map", table.concat(dealt_from, " | ") == "grenade | shotgun | ninja_rope", table.concat(dealt_from, " | "))

print("ALL PASS")
