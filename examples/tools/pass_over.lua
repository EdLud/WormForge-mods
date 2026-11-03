-- Pass-over test: worm.selectable and worm:input, as Specialists' zombies
-- will use them. The chosen worms are renamed "Passed over", WA's turns and
-- Tab skip them, and (walk option) they walk toward the worm whose turn it
-- is while its turn clock runs, whatever its team.
return function(ctx)
  local which = ctx.option("worms")
  local walk = ctx.option("walk")
  local chosen = function(worm)
    return which == "all" or worm.id % 16 == 1
  end
  local target, last_clock, running = nil, nil, false

  local function mark(worm)
    if worm.hp > 0 and chosen(worm) and worm.selectable then
      worm.selectable = false
      worm.name = "Passed over"
      wa.log("pass_over: worm " .. worm.id .. " passed over")
    end
  end

  wa.on.turn_start(function(event)
    for _, worm in ipairs(wa.worms.all()) do mark(worm) end
    target = event.worm
    if target then
      wa.log("pass_over: turn " .. tostring(target.id) .. (target.selectable and "" or " (a passed-over worm: WA had no other)"))
    end
  end)
  wa.on.turn_end(function() target, last_clock, running = nil, nil, false end)

  -- One frame message per worm. The turn clock counts down only once the
  -- turn runs (not in the hot-seat delay): the walkers wait for it.
  wa.on.worm_message(function(worm)
    mark(worm)
    if not target then return end
    if worm.id == target.id then
      local clock = wa.world.turn_clock()
      running = last_clock ~= nil and clock ~= nil and clock < last_clock
      last_clock = clock
      return
    end
    if not walk or not running or worm.selectable then return end
    if worm.state ~= "standing" and worm.state ~= "walking" then return end
    local dx = target.x - worm.x
    if dx > 20 then
      worm:input{ key = "right" }
    elseif dx < -20 then
      worm:input{ key = "left" }
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })
end
