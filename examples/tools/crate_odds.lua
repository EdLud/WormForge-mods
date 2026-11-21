-- Crate odds: changes the crate odds each round and drops a crate with a chosen weapon after
-- every turn, to try wa.crates.set_odds, set_shares and spawn{ contents }.

return function(ctx)
  local weapon, health, utility = ctx.option("weapon"), ctx.option("health"), ctx.option("utility")
  local favourite = ctx.option("favourite")
  local share = ctx.option("share")
  local gift = ctx.option("gift")

  local function share_of(shares, id)
    return shares.weapon[id] or shares.super[id] or shares.utility[id] or 0
  end

  wa.on.turn_start(function()
    -- The odds last until the round ends: a new round has the profile's again, so set them
    -- whenever they differ.
    local odds = wa.crates.odds()
    local same = odds.weapon == weapon and odds.health == health and odds.utility == utility
    if same and (not favourite or math.abs(share_of(wa.crates.shares(), favourite) - share) < 0.01) then return end
    wa.crates.set_odds{ weapon = weapon, health = health, utility = utility }
    if favourite then
      local ok, err = pcall(wa.crates.set_shares, { [favourite] = share })
      if not ok then
        -- Not on the panel this match: only the odds are set.
        wa.log("crate_odds: " .. tostring(err))
        favourite = nil
      end
    end
    odds = wa.crates.odds()
    wa.log(string.format("crate_odds: each turn weapon %g%%, health %g%%, utility %g%%, none %g%%",
      odds.weapon, odds.health, odds.utility, odds.none))
    local shares = wa.crates.shares()
    for _, kind in ipairs({ "weapon", "super", "utility" }) do
      for _, id in ipairs(wa.sorted(shares[kind])) do
        wa.log(string.format("crate_odds: %s %s %.2f%%", kind, id, shares[kind][id]))
      end
    end
  end)

  wa.on.turn_end(function(event)
    local worm = event.worm
    if not worm or gift == "none" then return end
    local ok, err = pcall(wa.crates.spawn, { x = worm.x, y = worm.y - 150, contents = gift, amount = 1 })
    if not ok then wa.log("crate_odds: " .. tostring(err)) end
  end)

  wa.on.hud(function()
    if not favourite then return end
    wa.hud.line(string.format("%s: %.2f%% of its crates", favourite, share_of(wa.crates.shares(), favourite)))
  end)
end
