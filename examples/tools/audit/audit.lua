-- All actions run on simulation callbacks. A hidden actor supplies the clock
-- across turn changes; render callbacks only display progress.
local all_cases = require("audit/cases")
return function(ctx)
  local instant = { ["stock.damage_x2"] = true, ["stock.crate_spy"] = true,
    ["stock.double_turn_time"] = true, ["stock.crate_shower"] = true }
  local late = {}
  for i = 62, #all_cases do late[all_cases[i]] = true end
  local cases = all_cases
  if ctx.options.scope == "sheep" then
    cases = { "stock.sheep_launcher", "stock.sheep", "stock.super_sheep", "stock.aqua_sheep" }
  elseif ctx.options.scope == "banana" then
    cases = { "stock.banana_bomb" }
  elseif ctx.options.scope == "utilities" then
    cases = {}
    for _, name in ipairs(all_cases) do
      if name == "stock.jet_pack" or #cases > 0 and #cases < 9 then cases[#cases + 1] = name end
    end
  elseif ctx.options.scope == "followup" then
    cases = {}
    for _, name in ipairs(all_cases) do
      if name == "stock.bungee" or instant[name] or late[name] then cases[#cases + 1] = name end
    end
  end
  -- WA consumes stock in these panel cells automatically, independently
  -- of the weapon placed there. Profiles start them empty. Give the case's
  -- weapon ammo explicitly, then clear these cells between cases;
  -- native activation during that case remains an observed slot tie.
  local automatic = { "stock.damage_x2", "stock.crate_spy", "stock.double_turn_time", "stock.crate_shower" }
  local automatic_set = {}
  for _, name in ipairs(automatic) do automatic_set[name] = true end
  for _, placed in ipairs(ctx.placed) do
    local pos = placed.position
    if pos.row == "utility" and pos.column >= 6 and not automatic_set[placed.id] then
      automatic[#automatic + 1] = placed.id
      automatic_set[placed.id] = true
    end
  end
  local function clear_automatic()
    for _, worm in ipairs(wa.worms.all()) do
      for _, name in ipairs(automatic) do worm:ammo(name, { set = 0 }) end
    end
  end

  local now, index, current, pending, next_at = 0, 0, nil, nil, 50
  local started, stopped, driver = false, false, nil
  local startup_worm, initialize
  local opening_worm
  local pending_since = 0
  local audit_worms, state, seen_missiles, seen_objects = {}, {}, {}, {}
  local released, quiet, last_motion = false, 0, nil
  local status = "Audit: waiting for first turn"

  local function json_string(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
      if c == '"' then return '\\"' end
      if c == '\\' then return '\\\\' end
      return string.format('\\u%04x', string.byte(c))
    end) .. '"'
  end

  -- Flat JSON objects only. Keys and hook payloads have stable order.
  local function emit(event, fields)
    fields = fields or {}
    fields.event = event
    if current then
      fields.test = current.name
      fields.frame = now - current.start
    end
    local parts = {}
    for _, k in ipairs(wa.sorted(fields)) do
      local v = fields[k]
      if type(v) == "string" then v = json_string(v)
      else v = tostring(v) end
      parts[#parts + 1] = string.format('"%s":%s', k, v)
    end
    wa.log("audit: {" .. table.concat(parts, ",") .. "}")
  end

  local function station(n)
    local i = n - 1
    return (i % 10) * 768 + 384, (i // 10) * 768 + 500
  end

  -- Ray samples at eight-pixel intervals in the station's 512-square region.
  -- Integer rolling hash: compare the baseline as well as the crater.
  local function land_digest(x, y)
    local hash = 1
    for dx = -256, 256, 8 do
      for dy = -128, 256, 8 do
        local hit = wa.land.trace(x + dx, y + dy, x + dx, y + dy + 7)
        local value = hit and (math.floor(hit.y * 16) % 65536 + 1) or 0
        hash = (hash * 65599 + value) % 2147483647
      end
    end
    return hash
  end

  local function live(id)
    for _, w in ipairs(wa.worms.all()) do
      if w.id == id and w.hp > 0 then return w end
    end
  end
  local function active()
    for _, w in ipairs(wa.worms.all()) do
      if w.hp > 0 and w.turn then return w end
    end
  end
  local function fail(reason)
    emit("error", { reason = reason })
    if wa.audit then pcall(wa.audit.finish) end
    stopped = true
    current, pending = nil, nil
    status = "Audit stopped: " .. reason
  end

  local function mobility_active(w)
    local s = w.state_id
    return s == 0x78 or s == 0x7B or s == 0x7C or s == 0x7D
  end

  local function launcher_live()
    return current.launcher_body and now - current.launcher_body.frame <= 2
  end

  local function finish(reason)
    if not current then return end
    local w = live(current.worm)
    if current.name == "stock.bungee" then
      emit("coverage", { action = "walk_off_edge", activated = current.bungee_seen == true,
        detached = current.bungee_detached == true })
    elseif current.name == "stock.sheep_launcher" then
      emit("coverage", { action = "sheep_launcher", airborne_drop = current.launcher_air_drop == true,
        airborne_explode = current.launcher_air_explode == true,
        landed_explode = current.launcher_landed_explode == true })
      if launcher_live() then fail("cannot advance: Sheep Launcher still has an active sheep"); return end
    elseif current.name == "stock.select_worm" then
      emit("coverage", { action = "select_worm", cycles = current.selection_cycles or 0,
        locked = current.selection_locked == true })
    end
    if w and mobility_active(w) then
      fail("cannot advance: worm is still using a mobility tool after " .. current.name)
      return
    end
    emit("end", {
      reason = reason, ammo = w and w:ammo(current.name) or -999,
      turn_ended = not w or not w.turn,
      land = land_digest(current.x, current.y),
    })
    wa.audit.finish()
    clear_automatic()
    current, pending = nil, nil
    next_at = now + 30
  end

  -- All audit worms are protected for the whole session. "eat" uses the
  -- existing hurt contract (skips WA's hurt handler, including its push).
  wa.on.hurt(function(hit)
    if not started or stopped or not audit_worms[hit.worm.id] or hit.phase ~= "pre" then return end
    if current then
      emit("hurt", { worm = hit.worm.id, kind = hit.kind, amount = hit.amount,
        source_weapon = hit.source_weapon or "unknown", weapon = hit.weapon or "unknown" })
    end
    return "eat"
  end)

  wa.on.worm_message(function(w, msg)
    -- turn_start runs before WA handles START_TURN. Wait until that worm
    -- has a live turn on a simulation frame before inspecting the round.
    if startup_worm == w.id and w.turn then
      startup_worm, started = nil, true
      initialize(w)
    end
    if not current then return end
    local s = w.state_id
    if w.id == current.worm and current.name == "stock.bungee" and s == 0x7C and not current.bungee_seen then
      current.bungee_seen = true
      emit("activation", { action = "bungee_attach" })
    end
    if w.id == current.worm and current.name == "stock.bungee" and current.detach_requested
        and not mobility_active(w) and not current.bungee_detached then
      current.bungee_detached = true
      emit("activation", { action = "bungee_detach" })
    end
    if state[w.id] ~= s then
      state[w.id] = s
      emit("state", { worm = w.id, state = s, msg = msg })
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })

  wa.on.missile_frame(function(m)
    if not current then return end
    if current.name == "stock.sheep_launcher" and m.weapon == current.name and m.phase == "post" then
      current.launcher_initial = current.launcher_initial or m.id
      current.launcher_body = { id = m.id, x = m.x, y = m.y, vx = m.vx, vy = m.vy, frame = now }
      -- A rocket promotes to a new sheep body on landing (or on the
      -- airborne activation). Require that transition plus three samples
      -- of near-zero vertical speed with terrain just below it.
      local ground = wa.land.trace(m.x, m.y, m.x, m.y + 12)
      local landed = m.id ~= current.launcher_initial and ground and math.abs(m.vy) < 0.25
      current.launcher_grounded = landed and (current.launcher_grounded or 0) + 1 or 0
    end
    if m.phase ~= "pre" then return end
    if not seen_missiles[m.id] then
      seen_missiles[m.id] = true
      emit("missile", { weapon = m.weapon or "unknown", x = m.x, y = m.y, vx = m.vx, vy = m.vy })
    end
  end)

  wa.on.turn_end(function(ev)
    -- Tab hands control to another worm without ending this test. Let
    -- the next simulation tick observe WA's active worm on the same team.
    if current and current.selection_active and ev.worm.team == current.team then return end
    if current and ev.worm.id == current.worm then finish("turn_end") end
  end)

  local cursor = { ["stock.homing_missile"] = true, ["stock.homing_pigeon"] = true,
    ["stock.magic_bullet"] = true, ["stock.girder"] = true, ["stock.girder_pack"] = true,
    ["stock.teleport"] = true }
  local sheep = { ["stock.sheep"] = 2, ["stock.super_sheep"] = 3, ["stock.aqua_sheep"] = 3 }
  -- Girders need open air: above the worm, halfway up the 576-pixel gap
  -- between its platform and the underside of the one above. The Starter
  -- Pack's girders go 20 pixels apart, centred on the worm.
  local girders = { ["stock.girder"] = 1, ["stock.girder_pack"] = 5 }
  local GIRDER_EVERY = 30
  local function girder_target(n)
    local first = -(girders[current.name] - 1) * 10
    return current.x + first + (n - 1) * 20, current.y - 288
  end
  local animals = { ["stock.mole_bomb"] = true,
    ["stock.salvation_army"] = true, ["stock.skunk"] = true, ["stock.old_woman"] = true }

  local function begin(w)
    if mobility_active(w) then fail("cannot begin a case while its worm is using a mobility tool"); return end
    local name = cases[index]
    local x, y = station(index)
    clear_automatic()
    if not instant[name] then w:ammo(name, { set = -1 }) end
    current = { name = name, worm = w.id, team = w.team, x = x, y = y, start = now,
      selection_active = name == "stock.select_worm" }
    if name == "stock.sheep_launcher" then current.launcher_phase = "airborne" end
    released, quiet, last_motion = false, 0, nil
    seen_missiles, seen_objects, state = {}, {}, {}
    emit("begin", { worm = w.id, station = index, x = x, y = y,
      ammo = w:ammo(name), land = land_digest(x, y) })
    wa.audit.begin(20261015)
    -- Every case gets the same, ample turn time: a turn running out part
    -- way through a case cut it short, and Double Time's result depends
    -- on the time left.
    wa.world.set_turn_clock(60000)
    local start_x = x
    if name == "stock.bungee" then start_x = x + 244
    elseif name == "stock.sheep_launcher" then start_x = x - 128 end
    w:warp{ x = start_x, y = y - 12, vx = 0, vy = 0, facing = 1 }
    if w.hp < 100 then w:heal(100 - w.hp) end
    local ammo = w:equip(instant[name] and "stock.bazooka" or name)
    if ammo == 0 then fail("equip refused for " .. name); return end
    if not instant[name] then w:input{ aim = 45, fuse = 3, bounce = "min" } end
    emit("setup", { ammo = w:ammo(name), hp = w.hp })
    status = string.format("Audit %d/%d: %s", index, #cases, name)
  end

  local function skip(w)
    w:equip("stock.skip_go")
    w:input{ fire = "press" }
    if live(w.id) then w:input{ fire = "release" } end
    next_at = now + 100
  end

  local function sample_motion(w)
    local parts = { tostring(w.state_id), tostring(w.x), tostring(w.y), tostring(w.vx), tostring(w.vy) }
    local busy = not (w.state_id == 0x65 or w.state_id == 0x67)
    for _, m in ipairs(wa.missiles.all()) do
      busy = true
      parts[#parts + 1] = tostring(m.uid) .. ":" .. tostring(m.x) .. ":" .. tostring(m.y)
    end
    for _, a in ipairs(wa.actors.all()) do
      if not driver or a.id ~= driver.id then busy = true end
    end
    for _, kind in ipairs({ "mines", "crates", "oil" }) do
      for _, obj in ipairs(wa[kind].all()) do
        local key = kind .. ":" .. tostring(obj.uid)
        if not seen_objects[key] then
          seen_objects[key] = true
          emit("body", { kind = kind, x = obj.x, y = obj.y })
        end
        if obj.vx ~= 0 or obj.vy ~= 0 then busy = true end
      end
    end
    return table.concat(parts, "/"), busy
  end

  local function tick()
    now = now + 1
    if stopped then return end
    if current then
      local age, name = now - current.start, current.name
      local w = live(current.worm)
      if current.selection_active then
        local controlled = active()
        if controlled and controlled.team == current.team then
          w, current.worm = controlled, controlled.id
        end
      end
      if not w then finish("removed"); return end
      if age > 40 and not w.turn then finish("turn_changed"); return end
      if instant[name] then
        -- Stocking one utility exercises WA's normal per-turn consumption
        -- after collection. Never equip or send fire for an instant utility.
        if age == 40 then
          w:ammo(name, { set = 1 })
          current.clock_before = wa.world.turn_clock()
          emit("utility_stock", { ammo = w:ammo(name) })
        elseif age == 55 then
          released = true
          emit("utility_result", { ammo = w:ammo(name), clock_delta = wa.world.turn_clock() - current.clock_before })
        end
      elseif name == "stock.bungee" then
        -- Bungee attaches on the walking-to-falling transition. A midair
        -- warp bypasses that native cliff check, as does the Parachute path.
        if age >= 40 and age < 90 then w:input{key = "right"}
        elseif age == 110 and current.bungee_seen then
          current.detach_requested = true
          w:input{fire = "press"}
        elseif age == 111 and current.bungee_seen then w:input{fire = "release"} end
        if age == 55 then released = true end
      elseif name == "stock.sheep_launcher" and current.launcher_phase == "landed" then
        local phase_age = age - current.launcher_phase_start
        if phase_age == 40 then
          emit("activation", { phase = "landed", step = 1, action = "launch", aim = w.aim })
          w:input{fire = "press"}
        elseif phase_age == 55 then
          w:input{fire = "release"}
        elseif phase_age > 55 and not current.launcher_landed_explode
            and launcher_live() and current.launcher_grounded >= 3 then
          emit("activation", { phase = "landed", step = 2, action = "explode",
            x = current.launcher_body.x, y = current.launcher_body.y, vy = current.launcher_body.vy })
          current.launcher_landed_explode = true
          current.launcher_release_at = age + 1
          w:input{fire = "press"}
        elseif age == current.launcher_release_at then
          w:input{fire = "release"}
        end
      elseif age == 40 then
        local data = wa.weapons.data(name)
        if girders[name] then
          local gx, gy = girder_target(1)
          w:input{ click = { x = gx, y = gy } }
        elseif cursor[name] or data.strike then
          w:input{ click = { x = current.x + 160, y = current.y - 8 } }
        end
        if not current then return end
        w = live(current.worm)
        if not w then finish("removed"); return end
        emit("aim", { aim = w.aim, state = w.state_id })
        w:input{ fire = "press" }
      elseif age == 55 then
        w:input{ fire = "release" }
        if not current then return end
        released = true
        emit("released", { ammo = w:ammo(name), state = w.state_id })
      elseif girders[name] and age > 40 and age < 40 + GIRDER_EVERY * girders[name] + 10 then
        -- Each girder: click, press, release; then see whether WA put it
        -- there (a rejected one leaves air at the click).
        local n = (age - 40) // GIRDER_EVERY + 1
        local step = (age - 40) % GIRDER_EVERY
        local gx, gy = girder_target(n)
        if step == 0 and n > 1 and n <= girders[name] then
          w:input{ click = { x = gx, y = gy } }
          if not current then return end
          w = live(current.worm)
          if not w then finish("removed"); return end
          w:input{ fire = "press" }
        elseif step == 15 and n > 1 and n <= girders[name] then
          w:input{ fire = "release" }
        elseif step == 25 and n <= girders[name] then
          emit("girder", { n = n, placed = wa.land.solid(gx, gy) })
        end
      elseif name == "stock.sheep_launcher" then
        if age == 90 and launcher_live() then
          local body = current.launcher_body
          if body.id == current.launcher_initial and not wa.land.trace(body.x, body.y, body.x, body.y + 12) then
            emit("activation", { phase = "airborne", step = 2, action = "drop", x = body.x, y = body.y })
            current.launcher_air_drop = true
            w:input{fire = "press"}
          end
        elseif age == 91 and current.launcher_air_drop then
          w:input{fire = "release"}
        elseif age == 140 and current.launcher_air_drop and launcher_live()
            and current.launcher_body.id ~= current.launcher_initial then
          emit("activation", { phase = "airborne", step = 3, action = "explode" })
          current.launcher_air_explode = true
          w:input{fire = "press"}
        elseif age == 141 and current.launcher_air_explode then
          w:input{fire = "release"}
        elseif age >= 200 and current.launcher_air_explode and not launcher_live() then
          current.launcher_phase, current.launcher_phase_start = "landed", age
          current.launcher_body, current.launcher_initial, current.launcher_grounded = nil, nil, 0
          emit("launcher_phase", { phase = "landed", land = land_digest(current.x, current.y) })
          -- A steep second launch lands on the station instead of crossing
          -- the inter-platform gap. Its activation waits for observed land.
          w:warp{x = current.x, y = current.y - 12, vx = 0, vy = 0, facing = 1}
          w:equip(name)
          w:input{aim = 85}
        end
      elseif name == "stock.select_worm" then
        if age == 90 or age == 120 then
          current.tab_from = w.id
          w:input{key = "tab"}
        elseif age == 91 or age == 121 then
          local changed = w.id ~= current.tab_from
          if changed then current.selection_cycles = (current.selection_cycles or 0) + 1 end
          emit("selection", { step = age == 91 and 1 or 2, from = current.tab_from,
            to = w.id, changed = changed })
        elseif age == 150 then
          emit("selection_confirm", { worm = w.id, key = "right" })
          w:input{key = "right"}
        elseif age == 170 then
          current.tab_from = w.id
          w:input{key = "tab"}
        elseif age == 171 then
          current.selection_locked = w.id == current.tab_from
          current.selection_active = false
          emit("selection_lock", { worm = w.id, locked = current.selection_locked })
        end
      elseif (name == "stock.shotgun" or name == "stock.longbow") and age == 100 then
        w:input{ fire = "press" }
      elseif (name == "stock.shotgun" or name == "stock.longbow") and age == 101 then
        w:input{ fire = "release" }
      elseif name == "stock.ninja_rope" then
        if age >= 65 and age < 85 then w:input{key = "left"}
        elseif age >= 85 and age < 105 then w:input{key = "up"}
        elseif age == 110 then w:input{fire = "press"}
        elseif age == 111 then w:input{fire = "release"} end
      elseif name == "stock.jet_pack" then
        if age >= 65 and age < 90 then w:input{key = "up"}
        elseif age >= 90 and age < 110 then w:input{key = "right"}
        elseif age == 115 then w:input{fire = "press"}
        elseif age == 116 then w:input{fire = "release"} end
      elseif name == "stock.parachute" then
        if age == 65 then w:warp{x = current.x + 280, y = current.y - 80, vx = 1, vy = 1}
        elseif age >= 70 and age < 95 then w:input{key = "right"}
        elseif age == 110 then w:input{fire = "press"}
        elseif age == 111 then w:input{fire = "release"} end
      elseif sheep[name] then
        if age == 90 then
          emit("activation", { step = 2, action = sheep[name] == 2 and "explode" or "fly" })
          w:input{fire = "press"}
        elseif age == 91 then
          w:input{fire = "release"}
        elseif sheep[name] == 3 then
          if age >= 95 and age < 110 then w:input{key = "left"}
          elseif age >= 110 and age < 125 then w:input{key = "right"}
          elseif age == 140 then
            emit("activation", { step = 3, action = "release" })
            w:input{fire = "press"}
          elseif age == 141 then w:input{fire = "release"} end
        end
      elseif animals[name] and (age == 140 or age == 240) then
        w:input{fire = "press"}
      elseif animals[name] and (age == 141 or age == 241) then
        w:input{fire = "release"}
      end
      -- Input can end the test reentrantly (turn_end, death). Never keep
      -- touching that test's worm after it has done so.
      if not current then return end
      w = live(current.worm)
      if not w then finish("removed"); return end
      if released and age >= 280 and (name ~= "stock.sheep_launcher" or current.launcher_landed_explode) then
        local motion, busy = sample_motion(w)
        if not busy and motion == last_motion then quiet = quiet + 1 else quiet = 0 end
        last_motion = motion
        if quiet >= 25 then finish("settled") end
      end
      if current and age >= 1000 then finish("timeout") end
      return
    end
    if now < next_at then return end
    local w = active()
    -- WA may choose any starting team. Reach a fixed first audit worm
    -- through ordinary Skip Go turns instead of requiring lucky restarts.
    if opening_worm then
      if now > 30000 then fail("opening worm never received a normal turn"); return end
      if w and w.id == opening_worm then
        opening_worm = nil
        wa.world.set_wind(0)
      else
        if w then skip(w) end
        return
      end
    end
    if pending and now - pending_since > 6000 then fail("fresh worm never received a normal turn"); return end
    if pending then
      if w and w.id == pending then begin(w)
      elseif w then skip(w) end
      return
    end
    if index == #cases then
      emit("complete", { tests = #cases })
      status, stopped = "Audit complete; save wkLua.log", true
      return
    end
    local next_name = cases[index + 1]
    if late[next_name] then
      index = index + 1
      local x, y = station(index)
      -- Split fresh cases across teams 1/2 so a three-worm starting roster
      -- never fills WA's eight-worm team limit. Keep team 3 for Surrender.
      local fresh = wa.worms.spawn{ team = next_name == "stock.surrender" and 3 or (1 + (index - 62) % 2),
        x = x, y = y - 12, health = 100, name = "Audit " .. index }
      audit_worms[fresh.id], pending = true, fresh.id
      pending_since = now
      emit("waiting", { worm = fresh.id, weapon = next_name })
      status = "Audit: waiting for fresh worm's normal turn"
      if w then skip(w) end
    elseif w then
      index = index + 1
      audit_worms[w.id] = true
      begin(w)
    end
  end

  initialize = function(first)
    local size = wa.world.size()
    local map_hash = 1
    emit("session", { version = 11, seed = 20261015, shift = ctx.options.shift, tests = #cases,
      rng = "fixture-v1", map = tostring(size.w) .. "x" .. tostring(size.h) })
    if not wa.audit then fail("requires a DLL built with --features input-audit"); return end
    if wa.world.networked() then fail("offline only"); return end
    if size.w ~= 7680 or size.h ~= 5376 then fail("load the generated Audit.png (7680x5376)"); return end
    local teams = {}
    -- Resolve through this round's entity, not the session pointer, which
    -- can still be unpublished during the initial turn_start callback.
    local all = wa.worms.all(first)
    for _, w in ipairs(all) do teams[w.team] = (teams[w.team] or 0) + 1 end
    if #all ~= 9 or #wa.sorted(teams) ~= 3 or teams[1] ~= 3 or teams[2] ~= 3 or teams[3] ~= 3 then
      fail("use three human teams with three worms each; team 3 is reserved for Surrender")
      return
    end
    for _, w in ipairs(all) do
      if w.hp ~= 100 then fail("set scheme worm health to 100"); return end
    end
    for i, w in ipairs(all) do
      audit_worms[w.id] = true
      if w.team == 1 and not opening_worm then opening_worm = w.id end
      -- Nine centres, twelve pixels apart, fit the existing reserve strip.
      w:warp{x = 24 + (i - 1) * 12, y = 5288, vx = 0, vy = 0, facing = 1}
    end
    for n = 1, #cases do
      local x, y = station(n)
      local hit = wa.land.trace(x, y - 40, x, y + 40)
      if not hit or math.abs(hit.y - y) > 2 then fail("audit station terrain does not match at " .. n); return end
      map_hash = (map_hash * 65599 + land_digest(x, y)) % 2147483647
    end
    emit("map", { digest = map_hash })
    status = "Audit: waiting for team 1's first worm's normal turn"
    -- Remove wind as a variable across the two independently started rounds.
    wa.world.set_wind(0)
    driver = wa.actors.spawn{
      owner = first, sprite = false, gravity = false, collide = false, persist = true,
      x = 64, y = 64,
      on = function()
        local ok, err = pcall(tick)
        if not ok then fail(tostring(err)) end
      end,
    }
  end
  wa.on.turn_start(function(ev)
    if started or startup_worm then return end
    startup_worm = ev.worm.id
  end)
  wa.on.hud(function() wa.hud.line(status, 14, 10) end)
end
