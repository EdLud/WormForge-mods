-- +N Seconds. Keep the component ID utilities.plus_ten so existing profiles
-- retain the weapon. Its amount is an option; how many bonuses a turn gets,
-- what extra pickups and retreat pickups do are its weapon settings, as for
-- WA's instant utilities (WormForge docs/instant-utilities.md).
local MAX_MS = 3600000

return {
  defaults = {
    ammo = { round_start = 0 },
    delay = 0,
    crate = { chance_pct = 40, type = "utility" },
    auto_use = true,
    after_use = "continue",
    -- WA's Double Time's own: one a turn, the surplus dropped, a retreat
    -- pickup used at once (docs/instant-utilities.md).
    uses_per_turn = 1,
    extra_pickups = "discard",
    retreat_collect = "activate",
  },
  install = function(ctx)
    local id = ctx.id
    local seconds = ctx.option("seconds")
    local data = ctx.data
    -- Bonuses a team may get in one turn: a count, or one per unit.
    local limit = data.uses_per_turn == "unlimited" and math.huge or (data.uses_per_turn or 1)
    local discard = (data.extra_pickups or "discard") == "discard"
    -- "nothing" is the older name for "discard".
    local retreat_collect = data.retreat_collect or "activate"
    if retreat_collect == "nothing" then retreat_collect = "discard" end
    local automatic = data.auto_use ~= false
    -- While worms are still being placed WA uses no instant utility, so a
    -- pickup waits for the team's first turn, as WA's Double Time does.
    local placing = wa.world.placing or function() return false end
    local used, pending, started = {}, nil, false

    -- Add up to `count` bonuses the turn still allows; how many it added.
    local function add_time(worm, count, retreat)
      count = math.min(count, limit - (used[worm.ammo_group] or 0))
      if count <= 0 then return 0 end
      local current = retreat and wa.world.retreat() or wa.world.turn_clock()
      local ms = math.min(current + seconds * count * 1000, MAX_MS)
      if retreat then
        if not wa.world.set_retreat(ms) then return 0 end
      else
        wa.world.set_turn_clock(ms)
      end
      used[worm.ammo_group] = (used[worm.ammo_group] or 0) + count
      return count
    end

    local function activate(worm, count, retreat)
      local held = worm:ammo(id)
      if held == 0 then return 0 end
      if held > 0 then count = math.min(count, held) end
      local added = add_time(worm, count, retreat)
      if added > 0 and held > 0 then worm:ammo(id, -added) end
      return added
    end

    local function discard_pickup(worm, count)
      -- Only remove newly awarded surplus, never older or infinite stock.
      local held = worm:ammo(id)
      if count > 0 and held > 0 then worm:ammo(id, -math.min(count, held)) end
    end

    local function collect(worm, count, retreat)
      local activated = activate(worm, count, retreat)
      if discard then discard_pickup(worm, count - activated) end
    end

    wa.weapons.replace({
      copy_from = "stock.double_turn_time",
      name = "+N Seconds",
      panel_icon = "sprites/plus_n.png",
      on_fire = function(fire)
        -- Native firing spends one unit. Refund it when this team has
        -- already had its turn's bonuses.
        if add_time(fire.worm, 1, wa.world.retreat() > 0) == 0 then
          if fire.worm:ammo(id) >= 0 then fire.worm:ammo(id, 1) end
        end
      end,
    })

    wa.on.turn_cleanup(function()
      used, pending, started = {}, nil, false
    end)
    if not automatic then return end -- Every pickup stays in inventory.

    wa.on.turn_start(function(ev)
      -- Native setup initializes the clock after StartTurn returns.
      if not started then pending = ev.worm.id end
    end)
    wa.on.worm_message(function(worm)
      if pending == worm.id and worm.turn and not placing() then
        pending, started = nil, true
        local held = worm:ammo(id)
        -- Infinite stock activates once, never an unbounded stack.
        activate(worm, held > 0 and held or 1, false)
      end
    end, { msgs = { wa.msg.FRAME_FINISH } })
    wa.on.weapon_grant(function(ev)
      local collector
      for _, worm in ipairs(wa.worms.all()) do
        if worm.id == ev.worm_id then collector = worm; break end
      end
      if not collector then return end
      for _, item in ipairs(ev.items) do
        if item.weapon == id and item.amount > 0 and not placing() then
          local retreat = wa.world.retreat() > 0
          if not retreat then
            collect(collector, item.amount, false)
          elseif retreat_collect == "activate" then
            collect(collector, item.amount, true)
          elseif retreat_collect == "discard" then
            discard_pickup(collector, item.amount)
          end -- "keep": bank the award for the next turn's automatic use.
        end
      end
    end)
  end,
}
