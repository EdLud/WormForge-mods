-- +10 Seconds: an instant utility of our own, in place of Double Time. It
-- adds ten seconds to the turn going on, whoever's it is.
--
-- Auto-Use is the profile's compatible on_collect="use" spelling: spend
-- one at turn start or on pickup if none was used this turn, bank the rest.
-- "keep" leaves every pickup stocked for manual firing.
--
-- It's built on Double Time's record: a utility, no aim, and the worm holds
-- WA's utility pose (wutllnk), which WA picks by the record's subtype. Its
-- on_fire replaces WA's utility fire, so Double Time's own bit and icon stay
-- off; WA's effect for Double Time is tied to id 69 anyway.
local SECONDS = 10
local MAX_MS = 3600000 -- what wa.world.set_turn_clock accepts

local function add_time(seconds)
  local ms = math.min(wa.world.turn_clock() + seconds * 1000, MAX_MS)
  wa.world.set_turn_clock(ms)
end

return {
  defaults = {
    ammo = { round_start = 0 },
    delay = 0,
    crate = { chance_pct = 40, type = "utility" },
    on_collect = "use",
    after_use = "continue",
  },
  install = function(ctx)
    local id = ctx.id
    local used = {}
    wa.weapons.replace({
      copy_from = "stock.double_turn_time",
      name = "+10 Seconds",
      panel_icon = "sprites/plus_ten.png",
      on_fire = function(fire)
        used[fire.worm.ammo_group] = true
        add_time(SECONDS)
      end,
    })
    if ctx.data.on_collect == "keep" then
      return
    end
    local pending
    local function auto_use(worm)
      if used[worm.ammo_group] then return end
      local held = worm:ammo(id)
      if held == 0 then return end
      if held > 0 then worm:ammo(id, -1) end
      used[worm.ammo_group] = true
      add_time(SECONDS)
    end
    wa.on.turn_start(function(ev)
      -- WA still initializes the turn clock after StartTurn returns.
      pending = ev.worm.id
    end)
    wa.on.worm_message(function(worm)
      if pending == worm.id and worm.turn then
        pending = nil
        auto_use(worm)
      end
    end, { msgs = { wa.msg.FRAME_FINISH } })
    wa.on.turn_cleanup(function()
      used = {}
      pending = nil
    end)
    wa.on.weapon_grant(function(ev)
      for _, item in ipairs(ev.items) do
        if item.weapon == id and item.amount > 0 then
          for _, worm in ipairs(wa.worms.all()) do
            if worm.id == ev.worm_id then
              auto_use(worm)
              break
            end
          end
        end
      end
    end)
  end,
}
