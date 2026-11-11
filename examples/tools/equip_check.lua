-- worm:equip check: four checks over team 1's first four turns, offline.

return function()
  local ID_SHOTGUN, ID_BAZOOKA, ID_SKIP = "stock.shotgun", "stock.bazooka", "stock.skip_go"
  local CANDIDATES = { "stock.super_banana", "stock.holy_grenade", "stock.banana_bomb",
    "stock.mortar", "stock.cluster_bomb", "stock.homing_missile", "stock.grenade" }
  local status = "equip check: waiting for team 1"
  local results, step, frame, team1, gift, turn_worm = {}, 0, 0, nil, nil, nil
  local given = false
  local bazookas, retreating, seen = 0, false, {}

  local function report(name, ok, detail)
    local line = ("equip check: %s %s (%s)"):format(name, ok and "PASS" or "FAIL", detail)
    wa.log(line)
    results[#results + 1] = line
    status = line
  end

  local function press(w, at, f)
    if f == at then pcall(w.input, w, { fire = "press" })
    elseif f == at + 15 then pcall(w.input, w, { fire = "release" }) end
  end

  local function skip(w, f)
    if f == 20 then w:equip(ID_SKIP) end
    press(w, 30, f)
  end

  wa.on.missile_frame(function(m)
    if m.phase == "pre" and retreating and m.weapon == ID_BAZOOKA and not seen[m.id] then
      seen[m.id] = true
      bazookas = bazookas + 1
    end
  end)

  wa.on.turn_start(function(ev)
    frame = 0
    retreating = false
    turn_worm = ev.worm and ev.worm.id
    if not team1 and ev.worm then team1 = ev.worm.team end
    if ev.worm and ev.worm.team == team1 then step = step + 1 end
  end)

  wa.on.turn_retreat(function(ev)
    if ev.worm and ev.worm.id == turn_worm then
      retreating = true
      if step == 1 and ev.worm.team == team1 then frame = 1000 end
    end
  end)

  wa.on.worm_message(function(w)
    if not team1 or w.id ~= turn_worm then return end
    if not w.turn and not retreating and frame < 100 then return end
    frame = frame + 1
    local f = frame
    if w.team ~= team1 then skip(w, f); return end

    if step == 1 then
      if f == 20 then
        local ammo = w:equip(ID_SHOTGUN)
        wa.log(("equip check: shotgun equipped, ammo %d"):format(ammo))
      end
      press(w, 40, f)
      if f == 90 then
        local got = w:equip(ID_BAZOOKA)
        report("mid-use refused", got == 0 and w.weapon == ID_SHOTGUN,
          ("equip returned %d, holding %s"):format(got, tostring(w.weapon)))
      end
      press(w, 110, f)
      if f == 1010 then
        local ok, got = pcall(w.equip, w, ID_BAZOOKA)
        got = ok and got or -1
        wa.log(("equip check: in the retreat, equip returned %d, holding %s"):format(got, tostring(w.weapon)))
      end
      press(w, 1020, f)
      if f == 1100 then
        report("no shot while WA has weapons off", bazookas == 0, ("bazooka missiles in the retreat: %d"):format(bazookas))
      end
    elseif step == 2 then
      if f == 20 then
        for _, id in ipairs(CANDIDATES) do
          if w:ammo(id) == 0 then gift = id; break end
        end
        if not gift then report("free shot fired", false, "no weapon with 0 ammo to test with"); return end
        local got = w:equip(gift)
        given = got == 1 and w:ammo(gift) == 1
        report("free shot given", given, ("%s: equip returned %d, ammo %d"):format(gift, got, w:ammo(gift)))
        w:input{ aim = 60, fuse = 5 }
      end
      if gift then
        press(w, 60, f)
        if f == 150 then
          report("free shot fired", given and w:ammo(gift) == 0, ("%s ammo after firing: %d"):format(gift, w:ammo(gift)))
        end
      end
    elseif step == 3 then
      if f == 15 and gift then
        report("fired gift not taken again", given and w:ammo(gift) == 0, ("%s ammo: %d"):format(gift, w:ammo(gift)))
        local got = w:equip(gift)
        given = got == 1
        wa.log(("equip check: %s given again, equip returned %d"):format(gift, got))
      end
      if f >= 20 then skip(w, f) end
    elseif step == 4 then
      if f == 15 and gift then
        report("unused gift taken back", given and w:ammo(gift) == 0, ("%s ammo at the next turn: %d"):format(gift, w:ammo(gift)))
        local passed = 0
        for _, r in ipairs(results) do if r:find("PASS") then passed = passed + 1 end end
        status = ("equip check: done, %d of %d passed"):format(passed, #results)
        wa.log(status)
      end
      if f >= 20 then skip(w, f) end
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })

  wa.on.hud(function() wa.hud.line(status, 14, 10) end)
end
