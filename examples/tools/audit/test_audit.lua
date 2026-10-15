-- Scheduler regression, including synchronous turn_end during input and
-- fresh worms waiting for WA's normal turn rotation. Does not simulate WA.
local root = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = root .. "/../?.lua;" .. package.path
local hooks, logs, worms, clock, selected, fixture = {}, {}, {}, nil, nil, false
local began, ended, fresh = {}, {}, {}
local turns = 0
local clock_sets = 0
local girder_clicks, girder_checks = { ["stock.girder"] = {}, ["stock.girder_pack"] = {} }, 0
local scope = arg[1] or "all"
local scenario = arg[3] or "valid"
local invalid_setup = scenario == "one" or scenario == "uneven" or scenario == "health"
local roster_ready, roster_reads, errors = false, 0, {}
local opening_skips, first_began = 0, false
local current_test, current_frame = nil, 0
local activations, steering = {}, {}
local utilities = { ["stock.damage_x2"] = true, ["stock.crate_spy"] = true,
  ["stock.double_turn_time"] = true, ["stock.crate_shower"] = true }
local utility_grants, bungee_steps, bungee_warps, bungee_fires = {}, 0, 0, 0
local selecting, select_tabs, select_changes, select_confirmed = false, 0, 0, false
local launcher_phase, launcher_phase_start, launcher_body, launcher_seq = 'airborne', 0, nil, 0
local launcher_presses = { airborne = {}, landed = {} }
local launcher_land_after = scenario == 'launcher_late_land' and 160 or 80
local instant = { "stock.damage_x2", "stock.crate_spy", "stock.double_turn_time", "stock.crate_shower" }
local shift = tonumber(arg[2]) or 0
if shift == 1 then instant = { "stock.invisibility", "stock.damage_x2", "stock.crate_spy", "stock.double_turn_time" } end
if shift == 35 then instant = { "stock.blow_torch", "stock.pneumatic_drill", "stock.girder", "stock.baseball_bat" } end
local cleared, physical = {}, {}
for _, name in ipairs(instant) do cleared[name], physical[name] = true, true end
for name in pairs(utilities) do cleared[name] = true end
local function register(name)
  return function(fn) hooks[name] = fn end
end
local function sorted(t)
  local keys = {}; for k in pairs(t) do keys[#keys+1] = k end
  table.sort(keys); return keys
end
local function rotate()
  if selected then
    local old = selected
    old.turn = false
    if hooks.turn_end then hooks.turn_end{worm=old} end
  end
  turns = turns + 1
  local living = {}
  for _, w in ipairs(worms) do
    if w.hp > 0 and not (scenario == "unscheduled" and fresh[w.id]) then living[#living+1] = w end
  end
  selected = living[(turns - 1) % #living + 1]
  selected.turn = true
end
local function make(team, health)
  local n = 0; for _, w in ipairs(worms) do if w.team == team then n = n+1 end end
  local w = {id=team*16+n+1,team=team,hp=health or 100,turn=false,state_id=0x67,x=0,y=0,vx=0,vy=0,aim=0.75}
  local ammo = {}
  for name in pairs(cleared) do ammo[name] = 0 end
  function w:ammo(name, change)
    if change and change.set == 1 and utilities[name] then
      assert(current_test == name and current_frame == 40, 'utility stocked outside its activation step')
      utility_grants[name] = (utility_grants[name] or 0) + 1
    end
    if change then ammo[name] = change.set end
    return ammo[name] == nil and -1 or ammo[name]
  end
  function w:heal(v) self.hp=self.hp+v end
  function w:warp(p)
    if current_test == 'stock.bungee' then
      bungee_warps = bungee_warps + 1
      assert(current_frame == 0 and p.vx == 0 and p.vy == 0, 'bungee must walk off the edge, not warp into a fall')
    end
    self.x,self.y=p.x,p.y;self.vx,self.vy=p.vx or 0,p.vy or 0;return true
  end
  function w:equip(name)
    assert(self.turn);assert(not utilities[name], 'instant utility cannot be equipped')
    self.weapon=name;return -1
  end
  function w:input(p)
    assert(not utilities[current_test], 'instant utility cannot receive input')
    if p.click and (current_test == 'stock.girder' or current_test == 'stock.girder_pack') then
      local clicks = girder_clicks[current_test]
      clicks[#clicks + 1] = { x = p.click.x - self.x, y = p.click.y - self.y, frame = current_frame }
    end
    if current_test == 'stock.sheep_launcher' and p.fire == 'press' then
      local presses = launcher_presses[launcher_phase]
      presses[#presses + 1] = current_frame
      if #presses == 1 then
        assert(current_frame == launcher_phase_start + 40, 'launcher fires after aiming')
        launcher_seq = launcher_seq + 1
        launcher_body = { id=launcher_seq, uid=launcher_seq, x=384, y=420, vx=8, vy=-3,
          weapon='stock.sheep_launcher', born=current_frame, kind='rocket' }
      elseif launcher_phase == 'airborne' and #presses == 2 then
        assert(current_frame == 90 and launcher_body.kind == 'rocket', 'second press must happen in the air')
        launcher_seq = launcher_seq + 1
        launcher_body.id, launcher_body.uid, launcher_body.kind = launcher_seq, launcher_seq, 'sheep'
      elseif launcher_phase == 'airborne' and #presses == 3 then
        assert(current_frame == 140 and launcher_body.kind == 'sheep', 'third airborne-path press detonates the walking sheep')
        launcher_body = nil
      elseif launcher_phase == 'landed' and #presses == 2 then
        assert(launcher_body and launcher_body.kind == 'sheep' and launcher_body.vy == 0,
          'second landed-path press waits for the sheep to land')
        assert(current_frame >= launcher_body.born + launcher_land_after + 3, 'wait for stable ground observations')
        launcher_body = nil
      else error('unexpected extra launcher shot') end
    end
    if current_test == 'stock.select_worm' then
      assert(self.turn, 'Select Worm inputs must follow the currently controlled worm')
      if p.fire == 'press' then
        selecting = true
      elseif p.key == 'tab' then
        select_tabs = select_tabs + 1
        if selecting then
          local team, at = {}, nil
          for _,other in ipairs(worms) do
            if other.team == self.team and other.hp > 0 then
              team[#team + 1] = other
              if other == self then at = #team end
            end
          end
          self.turn = false
          hooks.turn_end{worm=self} -- handover is synchronous, not a case end
          selected = team[at % #team + 1]
          hooks.turn_start{worm=selected}
          selected.turn = true
          select_changes = select_changes + 1
        end
      elseif p.key == 'right' then
        assert(select_changes == 2 and current_frame == 150, 'confirm follows both Tab changes')
        selecting, select_confirmed = false, true
      end
    end
    if current_test == 'stock.bungee' then
      if p.key == 'right' then
        bungee_steps = bungee_steps + 1
        if bungee_steps == 20 then self.state_id = 0x7C end
      elseif p.fire == 'press' then
        assert(current_frame == 110 and self.state_id == 0x7C, 'bungee only fires to detach after attachment')
        bungee_fires = bungee_fires + 1
        if scenario ~= 'stuck_bungee' then self.state_id = 0x67 end
      end
    end
    if current_test and current_test:match("sheep$") then
      if p.fire == "press" then
        activations[current_test] = activations[current_test] or {}
        table.insert(activations[current_test], current_frame)
      elseif p.key then
        steering[current_test] = (steering[current_test] or 0) + 1
      end
    end
    if p.fire == 'press' and self.weapon == 'stock.skip_go' then
      if not first_began then opening_skips = opening_skips + 1 end
      rotate()
    elseif p.fire == 'press' and self.weapon == 'stock.surrender' then
      for _, other in ipairs(worms) do if other.team == self.team then other.hp = 0 end end
      rotate()
    end
  end
  worms[#worms+1]=w;return w
end
local counts = scenario == "one" and {1,1,1} or scenario == "uneven" and {2,3,4} or {3,3,3}
for t=1,3 do for _=1,counts[t] do make(t) end end
if scenario == "health" then worms[#worms].hp = 99 end
wa = {
  sorted=sorted, math={}, msg={FRAME_FINISH=2},
  audit={begin=function() assert(not fixture);fixture=true end,finish=function() fixture=false end},
  log=function(line)
    logs[#logs+1]=line
    local event=line:match('"event":"([^"]+)"')
    local test=line:match('"test":"([^"]+)"')
    if event == 'error' then
      errors[#errors + 1] = line
      assert(invalid_setup or scenario == "unscheduled" or scenario == "stuck_bungee"
        or scenario == 'launcher_no_land' or scenario == 'launcher_early_land', line)
    end
    if event=='begin' then
      if not first_began then
        assert(tonumber(line:match('"worm":(%d+)')) == 17, 'first audit case must use team 1 worm 1')
        if scenario:match('^starter') then assert(opening_skips > 0, 'opening turns were not skipped normally') end
        first_began = true
      end
      assert(not began[test]);began[test]=true
      current_test, current_frame = test, 0
    end
    if event == 'launcher_phase' then
      assert(not launcher_body, 'previous launched sheep must be gone before the next path')
      launcher_phase, launcher_phase_start = 'landed', current_frame
    end
    if event=='end' then assert(began[test]);assert(not ended[test]);ended[test]=true;current_test=nil end
    if event == 'coverage' and test == 'stock.bungee' then
      assert(line:find('"activated":true',1,true), 'bungee attachment must be observed')
      assert(line:find('"detached":' .. tostring(scenario ~= 'stuck_bungee'),1,true), 'detach result must be observed')
    end
    if event == 'coverage' and test == 'stock.select_worm' then
      assert(line:find('"cycles":2',1,true) and line:find('"locked":true',1,true), 'Select Worm must observe two handovers and a locked choice')
    end
    if event == 'coverage' and test == 'stock.sheep_launcher' then
      local air = tostring(scenario ~= 'launcher_early_land')
      assert(line:find('"airborne_drop":' .. air,1,true) and line:find('"airborne_explode":' .. air,1,true), 'airborne launcher chain follows observed flight')
      assert(line:find('"landed_explode":' .. tostring(scenario ~= 'launcher_no_land' and scenario ~= 'launcher_early_land'),1,true), 'landed result follows ground observations')
    end
  end,
  world={size=function() return {w=7680,h=5376} end,networked=function() return false end,
    set_wind=function() end,turn_clock=function() return 90000 end,
    set_turn_clock=function(ms) assert(ms == 60000, 'every case starts with 60 s'); clock_sets = clock_sets + 1 end},
  land={solid=function(x,y) girder_checks = girder_checks + 1; return true end,
    trace=function(x,y,_,bottom)
    local surface=(y//768)*768+500
    if y<=surface and bottom>=surface then return {x=x,y=surface} end
  end},
  worms={all=function(from)
      if not roster_ready then
        assert(from == selected, 'startup roster must resolve through the new round worm')
        roster_reads = roster_reads + 1
      end
      local a={};for _,w in ipairs(worms) do if w.hp>0 then a[#a+1]=w end end;return a
    end,
    spawn=function(p)
      local living = 0;for _,w in ipairs(worms) do if w.team == p.team and w.hp > 0 then living = living + 1 end end
      assert(living < 8, 'WA team capacity exceeded')
      local w=make(p.team,p.health);fresh[w.id]=true;return w
    end},
  weapons={data=function() return {} end},
  missiles={all=function() return launcher_body and { launcher_body } or {} end},
  actors={all=function() return { {id=1} } end,spawn=function(p) clock=p.on;return {id=1} end},
  mines={all=function() return {} end},crates={all=function() return {} end},oil={all=function() return {} end},
  hud={line=function() end},
  on={hurt=register('hurt'),worm_message=register('worm_message'),missile_frame=register('missile_frame'),
      turn_end=register('turn_end'),turn_start=register('turn_start'),hud=register('hud')},
}
local install=assert(loadfile(root .. '/audit.lua'))()
local placed = {}
for i, name in ipairs(instant) do placed[i] = {id=name, position={row="utility",column=i+5}} end
install{options={shift=shift,scope=scope},placed=placed}
rotate()
local first_index = ({starter=4, starter3=7, starter_worm=2})[scenario]
if first_index then
  selected.turn = false; selected = worms[first_index]; selected.turn = true
  turns = first_index
end
-- Native START_TURN has not yet set the active flag or published the
-- session. Neither that hook nor an inactive frame may validate the roster.
selected.turn = false
hooks.turn_start{worm=selected}
assert(not clock and #logs == 0 and roster_reads == 0, 'startup ran inside START_TURN')
hooks.worm_message(selected, wa.msg.FRAME_FINISH)
assert(not clock and #logs == 0 and roster_reads == 0, 'startup ran before the turn became active')
selected.turn = true
hooks.worm_message(worms[#worms], wa.msg.FRAME_FINISH)
assert(not clock and #logs == 0 and roster_reads == 0, 'another worm initialized the audit')
hooks.worm_message(selected, wa.msg.FRAME_FINISH)
assert(roster_reads == 1, 'new round roster was not read once through its worm')
roster_ready = true
if invalid_setup then
  assert(not clock and #errors == 1, 'invalid setup must stop once before spawning the clock')
  local expected = scenario == "health" and "set scheme worm health" or "three worms each"
  assert(errors[1]:find(expected,1,true),errors[1])
  hooks.turn_start{worm=selected}
  hooks.worm_message(selected, wa.msg.FRAME_FINISH)
  assert(#errors == 1, 'failed startup was retried')
  print('Audit startup: rejected ' .. scenario .. ' setup after START_TURN')
  return
end
assert(clock)
local positions = {}
for _,w in ipairs(worms) do
  assert(w.x >= 22 and w.x <= 122 and w.y == 5288, 'waiting worm is outside reserve strip')
  assert(not positions[w.x], 'waiting worms overlap')
  positions[w.x] = true
end
assert(logs[1]:find('"version":11',1,true), 'girders placed in open air are a fresh protocol')
for _=1,60000 do
  if current_test then current_frame=current_frame+1 end
  if utilities[current_test] and physical[current_test] and current_frame == 41 then
    selected:ammo(current_test,{set=0}) -- native per-turn consumption
  end
  clock()
  if launcher_body then
    local lands = launcher_phase == 'landed' and current_frame >= launcher_body.born + launcher_land_after
      and scenario ~= 'launcher_no_land'
    if (lands or (scenario == 'launcher_early_land' and current_frame >= launcher_body.born + 20))
        and launcher_body.kind == 'rocket' then
      launcher_seq = launcher_seq + 1
      launcher_body.id, launcher_body.uid, launcher_body.kind = launcher_seq, launcher_seq, 'sheep'
      launcher_body.y, launcher_body.vy = 493, 0
    end
    launcher_body.phase = 'pre'; hooks.missile_frame(launcher_body)
    launcher_body.phase = 'post'; hooks.missile_frame(launcher_body)
  end
  for _,w in ipairs(worms) do hooks.worm_message(w,wa.msg.FRAME_FINISH) end
  for _, w in ipairs(worms) do
    for name in pairs(cleared) do
      local expected = 0
      if current_test == name and w == selected then
        if utilities[name] then
          if current_frame >= 40 and (not physical[name] or current_frame == 40) then expected = 1 end
        else expected = -1 end
      end
      assert(w:ammo(name) == expected,
        "automatic utility stock leaked outside its own case: " .. name)
    end
  end
  if logs[#logs]:find('"event":"complete"',1,true) then break end
  if #errors > 0 then break end
end
if scenario == "unscheduled" then
  assert(#errors == 1 and errors[1]:find('fresh worm never received a normal turn',1,true), 'missing turn must stop with a clear error')
  assert(not fixture, 'stalled scheduler released the RNG fixture')
  print('Audit scheduler: an unscheduled fresh worm stops after the bounded wait')
  return
end
if scenario == 'stuck_bungee' then
  assert(scope == 'followup', 'stuck fixture uses the Bungee-first followup scope')
  assert(#errors == 1 and errors[1]:find('still using a mobility tool',1,true), 'stuck bungee must stop')
  assert(began['stock.bungee'] and not ended['stock.bungee'] and not began['stock.damage_x2'], 'stuck bungee cannot contaminate later cases')
  assert(not fixture, 'failed detach released the RNG fixture')
  print('Audit scheduler: failed Bungee detach stops before the next case')
  return
end
if scenario == 'launcher_no_land' or scenario == 'launcher_early_land' then
  assert(scope == 'sheep', 'launcher watchdog fixture uses the sheep scope')
  assert(#errors == 1 and errors[1]:find('Sheep Launcher still has an active sheep',1,true))
  assert(not began['stock.sheep'] and not fixture, 'a surviving launcher sheep cannot contaminate the next case')
  if scenario == 'launcher_no_land' then assert(#launcher_presses.landed == 1, 'no activation is guessed before landing')
  else assert(#launcher_presses.airborne == 1 and #launcher_presses.landed == 0, 'no airborne drop is guessed after landing') end
  print('Audit scheduler: missing launcher landing stops before the next case')
  return
end
local count=0;for _ in pairs(ended) do count=count+1 end
assert(count==(scope == "sheep" and 4 or scope == "followup" and 14 or scope == "utilities" and 9 or 70),'ended '..count..' tests')
if scope == "utilities" then
  for name in pairs(utilities) do assert(utility_grants[name] == 1, name .. ': stock one utility once') end
elseif scope ~= "sheep" then
  assert(began['stock.surrender'] and ended['stock.surrender'],'last pending test ran')
  assert(bungee_steps == 50 and bungee_warps == 1 and bungee_fires == 1, 'bungee cliff sequence')
  assert(select_tabs == 3 and select_changes == 2 and select_confirmed and not selecting, 'Tab cycles until Right confirms the choice')
  for name in pairs(utilities) do assert(utility_grants[name] == 1, name .. ': stock one utility once') end
end
if scope ~= "followup" and scope ~= "utilities" then
assert(#launcher_presses.airborne == 3 and #launcher_presses.landed == 2, 'both launcher activation paths ran without an extra launch')
for name, expected in pairs({['stock.sheep']={40,90},['stock.super_sheep']={40,90,140},['stock.aqua_sheep']={40,90,140}}) do
  local got=assert(activations[name],name)
  assert(#got==#expected,name .. ': incorrect activation count')
  for i,frame in ipairs(expected) do assert(got[i]==frame,name .. ': incorrect activation timing') end
end
assert(not steering['stock.sheep'],'normal sheep is not flown')
assert(steering['stock.super_sheep']==30 and steering['stock.aqua_sheep']==30,'both flying sheep are steered')
end
assert(clock_sets == count, 'every case set the turn clock')
if scope == 'all' then
  -- The worm stands 12 pixels above its station; the girders go 288 above
  -- the station, in the open air of the gap, 20 pixels apart.
  local g, p = girder_clicks['stock.girder'], girder_clicks['stock.girder_pack']
  assert(#g == 1 and g[1].x == 0 and g[1].y == -276 and g[1].frame == 40, 'one girder above the worm')
  assert(#p == 5, 'five Starter Pack girders')
  for i, c in ipairs(p) do
    assert(c.x == -40 + (i - 1) * 20 and c.y == -276 and c.frame == 40 + (i - 1) * 30, 'girder ' .. i)
  end
  assert(girder_checks == 6, 'each girder checked once, got ' .. girder_checks)
end
assert(not fixture,'RNG fixture released')
print('Audit scheduler: '..count..' tests completed ('..scenario..'); opening turn, sheep controls and automatic utility stock passed')
