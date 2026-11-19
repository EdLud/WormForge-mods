-- The Lightning Strike's hooks without Highlander's rules: a profile such as
-- Specialists sets the weapon up with no scheme state, then a worm is revived
-- and healed.
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  print((ok and "  ok   " or "  FAIL ") .. name .. (detail and ("   [" .. tostring(detail) .. "]") or ""))
  if not ok then failed = failed + 1 end
end

-- wf-lib/lightning keeps the hooks px gives it; lib/electrical has no targets.
local hooks
package.preload["wf-lib/lightning"] = function()
  return {
    extend = function(t) hooks = t end,
    setup = function() end,
  }
end
package.preload["lib/electrical"] = function()
  return {
    special_on_beam = function() return nil end,
    special_targets = function() return {} end,
  }
end

local weapon = dofile(root .. "weapons/lightning_strike.lua")
local ok, err = pcall(weapon.setup)
check("setup runs with no scheme state", ok, err)
check("setup gives the strike its hooks", hooks ~= nil)

local worm = { id = 17 }
ok, err = pcall(function() return hooks.heals(worm) end)
check("a worm Lightning never revived is healed", ok and err == true, err)
ok, err = pcall(hooks.revived, worm)
check("a revive is recorded", ok, err)
ok, err = pcall(function() return hooks.heals(worm) end)
check("the worm Lightning revived isn't healed", ok and err == false, err)

if failed > 0 then
  print(failed .. " failed")
  os.exit(1)
end
print("all passed")
