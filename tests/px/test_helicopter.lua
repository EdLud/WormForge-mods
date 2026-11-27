-- lua mods/tests/px/test_helicopter.lua
-- Helicopter Dash: while Shift is held the heli flies as normal, only faster (at the Dash steering share of
-- its grip), then coasts on; the fuel drains and refills, the bar draws.
-- Each press costs part of the bar; run dry, the bar turns red until it's full again.
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

package.loaded["wf-lib/own_time"] = { frames = function() return 1 end }
local hints = {}
package.loaded["lib/weapon_hint"] = { hint = function(id, reader) hints[id] = reader end }

local function check(what, ok, detail)
  if not ok then error("FAIL: " .. what .. (detail and ("   [" .. tostring(detail) .. "]") or ""), 2) end
  print("  ok   " .. what)
end

local function near(a, b) return math.abs(a - b) < 1e-9 end

local function push(v, dir)
  local s = -dir * v
  if s > -1 then s = s - 0.2 end
  if s > -4 then s = s - 0.4 end
  if s > -8 then s = s - 0.15 end
  if s > -10 then s = s - 0.05 end
  return -dir * s
end

-- One frame of the dash as the pack works it out: normal flight at 1/k of the speed, at
-- `steer` of its grip and slowing, the whole speed held to 5k; no arrow speeds it up the way it goes.
local function dash_step(vx, vy, keys, k, steer, facing)
  k, steer, facing = k or 3, steer or 0.5, facing or 1
  local x, y = vx / k, vy / k
  if not (keys.up or keys.down or keys.left or keys.right) then
    local s = math.sqrt(x * x + y * y)
    local dx, dy = facing, 0
    if s * k >= 1 then dx, dy = x / s, y / s end
    s = s + (push(s, 1) - s) * steer
    x, y = dx * s, dy * s
  else
    if not keys.up and not keys.down then y = y / (1 + 0.105 * steer) end
    if not keys.left and not keys.right then x = x / (1 + 0.105 * steer) end
    if keys.up and keys.down then y = y / 1.095 end
    if keys.left and keys.right then x = x / 1.095 end
    if keys.up then y = y + (push(y, -1) - y) * steer end
    if keys.down then y = y + (push(y, 1) - y) * steer end
    if keys.left then x = x + (push(x, -1) - x) * steer end
    if keys.right then x = x + (push(x, 1) - x) * steer end
  end
  local s = math.sqrt(x * x + y * y)
  if s > 5 then x, y = x * 5 / s, y * 5 / s end
  return x * k, y * k
end

local function dash_frames(vx, vy, keys, n, k, steer, facing)
  for _ = 1, n do vx, vy = dash_step(vx, vy, keys, k, steer, facing) end
  return vx, vy
end

local handlers, draws, quads, ribbons, spawned, worms, shift, pops, booms

local function new_match(options)
  handlers, draws, quads, ribbons, spawned, worms, shift, pops = {}, {}, {}, {}, {}, {}, false, {}
  booms = {}
  wa = {
    depth = { FRONT = 0x10000 },
    msg = { FRAME_FINISH = 2 },
    on = {
      worm_message = function(f) handlers[#handlers + 1] = f end,
      draw = function(f) draws[#draws + 1] = f end,
    },
    sound = { play = function(_, id, opts)
      if id == 115 then pops[#pops + 1] = opts and opts.pitch end
    end },
    random = function() return 1 end,
    math = { sin = math.sin, atan = math.atan },
    actors = {
      spawn = function(spec)
        local a = { sprite = spec.sprite, explode = spec.explode }
        function a:gfx(g) for k, v in pairs(g) do self[k] = v end end
        function a:frame(i) self.shown = i end
        function a:remove() self.dead = true end
        spawned[#spawned + 1] = a
        return a
      end,
    },
    world = {
      keys = function() -- the synchronized keys: Shift, and the arrows the worm holds
        local k = worms[1] and worms[1].keys or {}
        return { shift = shift, up = k.up, down = k.down, left = k.left, right = k.right }
      end,
      water = function() return 10000 end,
      retreat = function() return 0 end,
      frame = function() return 0 end,
      explode = function(spec) booms[#booms + 1] = spec end,
    },
    draw = {
      quad = function(q) quads[#quads + 1] = q end,
      ribbon = function(r)
        for _, p in ipairs(r.points) do -- the engine reads these fields by name
          for _, key in ipairs({ "x", "y", "width", "u" }) do
            assert(type(p[key]) == "number" and p[key] == p[key], "ribbon point " .. key)
          end
        end
        ribbons[#ribbons + 1] = { sprite = r.sprite, n = #r.points, alpha = r.points[3].color >> 24 }
      end,
      fraction = function() return 0 end,
    },
    worms = { all = function() return worms end },
  }
  dofile(root .. "../tests/brush_mock.lua")(wa)
  package.loaded["lib/shared"] = nil
  local weapon = dofile(root .. "weapons/helicopter.lua")
  local values = { fuel = 100, acceleration = 100, dash_fuel = 1000, dash_speed = 300, dash_steer_factor = 50, dash_refill_factor = 30,
    dash_use_cost = 0, crash_speed_scale = 0 }
  for k, v in pairs(options or {}) do values[k] = v end
  weapon.configure({ option = function(key) return values[key] end }, { jet_pack = {} })
  weapon.setup()
  local w = { id = 3, x = 500, y = 300, vx = 0, vy = 0, facing = 1, gravity = 1, wind = 0, fuel = 100,
    state = "prefiring", weapon = "px.helicopter", turn = true, body_visible = true, keys = {} }
  function w:jetpack_steer(on, opts)
    self.steer = tostring(on) .. ((opts and opts.speed_limit == false) and " unlimited" or " limited")
  end
  worms[1] = w
  return w
end

local function frame(w, n)
  for _ = 1, n or 1 do
    for _, f in ipairs(handlers) do f(w, wa.msg.FRAME_FINISH) end
  end
end

local function take_off(w)
  frame(w)
  w.state = "jetpacking"
  frame(w)
end

local function draw()
  quads, ribbons = {}, {}
  for _, f in ipairs(draws) do f() end
  return quads
end

local function width(q) return q.points[2][1] - q.points[1][1] end

local function strongest()
  local top = 0
  for _, r in ipairs(ribbons) do top = math.max(top, r.alpha) end
  return top
end

local BAR, FRAME = "sprites/helicopter/dash_bar.png", "sprites/helicopter/dash_frame.png"
local GLOW, LINE = "sprites/helicopter/dash_glow.png", "sprites/helicopter/dash_line.png"

local function sheets(list, sheet)
  local found = {}
  for _, q in ipairs(list) do if q.sprite == sheet then found[#found + 1] = q end end
  return found
end

print("helicopter dash: direction, ramp, lock, steering, fuel")
do
  local w = new_match()
  check("its tooltip tells the player about the dash", hints["px.helicopter"](w) == "Helicopter\nPress Shift to dash")
  take_off(w)
  check("the take-off's full bar makes no pop", #pops == 0)
  local body = spawned[#spawned]
  body.x, body.y = 503.5, 301.25 -- drawn ahead of the worm, as the follow puts it
  local bars, frames = sheets(draw(), BAR), sheets(quads, FRAME)
  check("flying: a full stock-blue bar in its outline, above the heli's drawn place",
    #bars == 2 and #frames == 1 and near(width(bars[2]), 40) and bars[2].color == 0xFF9C9DFE
    and near(width(frames[1]), 44) and frames[1].points[1][1] == 482 and frames[1].points[3][2] < body.y - 21
    and #sheets(quads, GLOW) == 0 and #ribbons == 0, frames[1].points[1][1])

  w.keys = { up = true, right = true }
  shift = true
  frame(w)
  local ex, ey = dash_step(0, 0, w.keys)
  check("Shift with up and right: normal flight's push, 3 times as big at half its grip, no gravity or wind",
    near(w.vx, ex) and near(w.vy, ey) and near(w.vx, 1.2) and w.gravity == 0 and w.wind == 0, w.vx .. "," .. w.vy)
  frame(w)
  check("the heli turns its nose the way it goes, 30 degrees a frame", math.abs(body.angle - 315) < 1e-6, body.angle)
  local level = frames[1].points[1][2]
  body.x, body.y = 503.5, 301.25
  local tilted = sheets(draw(), FRAME)[1]
  check("the bar keeps its height over the tilted heli", tilted.points[1][2] == level and level == 266,
    tilted.points[1][2] .. " " .. level)
  frame(w, 28)
  ex, ey = dash_frames(0, 0, w.keys, 30)
  check("held, up and right reach 300% of the heli's top speed (5) together: a diagonal is no faster",
    near(w.vx, ex) and near(math.sqrt(w.vx * w.vx + w.vy * w.vy), 15) and near(w.vx, -w.vy)
    and w.steer == "true unlimited", w.vx .. "," .. w.vy)

  w.keys = { down = true }
  local vx0, vy0 = w.vx, w.vy
  frame(w, 30)
  ex, ey = dash_frames(vx0, vy0, w.keys, 30)
  check("down turns it any way, as in normal flight: the unheld axis slows at half the rate",
    near(w.vx, ex) and near(w.vy, ey) and w.vy > 10 and w.vx < 3, w.vx .. "," .. w.vy)
  w.keys = {}
  vx0, vy0 = w.vx, w.vy
  frame(w, 10)
  ex, ey = dash_frames(vx0, vy0, w.keys, 10)
  check("no arrow: it keeps on the way it goes, at the dash's speed",
    near(w.vx, ex) and near(w.vy, ey) and near(w.vx / w.vy, vx0 / vy0)
    and near(math.sqrt(w.vx * w.vx + w.vy * w.vy), 15), w.vx .. "," .. w.vy)

  bars = sheets(draw(), BAR)
  local lines = sheets(ribbons, LINE)  bars = sheets(draw(), BAR)
  local lines = sheets(ribbons, LINE)
  check("dashing: the fill turns red and glows, streaks of air flow round the heli",
    bars[2].color == 0xFFFE6A5A and #sheets(quads, GLOW) == 1 and #lines > 20 and #lines == #ribbons
    and lines[1].n == 5, #lines)
  local dashing, dashing_count = strongest(), #ribbons

  frame(w, 80)
  check("1000 fuel (100 units) lasts 150 frames", w.gravity == 0, w.gravity)
  frame(w)
  check("empty: the dash ends, the heli's gravity and wind back", w.gravity == 0.2 and w.wind == 0.2)
  local vx, vy = w.vx, w.vy
  frame(w)
  local drag = 1 / (1 + 0.0015 * math.sqrt(vx * vx + vy * vy))
  local function braked(v) return v / (1 + 0.105 * math.min(1, 5 / math.abs(v)) ^ 8) end
  check("then it coasts: air drag by the square of its speed, then braking that grows near the top speed",
    near(w.vx, braked(vx * drag)) and near(w.vy, braked(vy * drag)), w.vx)
  frame(w, 3)
  check("still holding Shift starts no new dash", w.gravity == 0.2)
  check("5 frames on it's still faster than the heli flies, the limit still lifted",
    math.sqrt(w.vx * w.vx + w.vy * w.vy) > 5 and w.steer == "true unlimited", w.vx .. "," .. w.vy)
  draw()
  check("and the air lines thin out with it: fewer and fainter", #ribbons > 0 and #ribbons < dashing_count
    and strongest() < dashing, #ribbons .. " < " .. dashing_count .. ", " .. strongest() .. " < " .. dashing)

  frame(w, 17)
  shift = false
  frame(w, 49)
  bars = sheets(draw(), BAR)
  check("the refill runs from the dash's end at 30% of the burn: 71 frames, 14.2 fuel",
    near(width(bars[2]), 40 * 0.3 * 71 / 150), width(bars[2]))
  check("slowed to the heli's own speed, the coast is over and the limit back",
    math.abs(w.vx) <= 5 and math.abs(w.vy) <= 5 and strongest() == 0 and w.steer == "true limited", w.steer)
  shift = true
  frame(w)
  bars, frames = sheets(draw(), BAR), sheets(quads, FRAME)
  check("run dry, the bar refills red and Shift doesn't dash",
    w.gravity == 0.2 and #pops == 0 and bars[2].color == 0xFFD8282E and frames[1].color == 0xFFFF7070,
    string.format("%X", bars[2].color))
  shift = false
  local waited = 0
  while #pops == 0 and waited < 1000 do frame(w); waited = waited + 1 end
  check("full again after 128.7 more frames: the crate pop, an octave up",
    waited == 429 and pops[1] == 12, waited .. " frames, pitch " .. tostring(pops[1]))
  frame(w, 10)
  check("once", #pops == 1)
  w.vx, w.vy = -4, 3
  shift = true
  w.facing = 1
  frame(w)
  bars, frames = sheets(draw(), BAR), sheets(quads, FRAME)
  check("full again: the outline is white again", frames[1].color == 0xFFFFFFFF)
  ex, ey = dash_step(-4, 3, {})
  check("moving, Shift with no arrow speeds it up the way it goes and turns it that way",
    near(w.vx, ex) and near(w.vy, ey) and near(w.vx / w.vy, -4 / 3) and w.facing == -1, w.vx .. "," .. w.vy)
end

print("helicopter coast: no sudden stop, and wind can't keep it going")
for _, held in ipairs({ {}, { right = true } }) do
  local w = new_match()
  take_off(w)
  shift, w.keys = true, held
  frame(w, 15)
  shift = false
  local speeds, frames = { w.vx }, 0
  repeat
    frame(w)
    w.vx = w.vx + 0.05 -- a strong tailwind, which WA adds and the mock leaves out
    w.vx = math.min(w.vx, w.steer == "true limited" and 5 or math.huge) -- WA's limit, back after the coast
    speeds[#speeds + 1] = w.vx
    frames = frames + 1
  until (held.right and w.steer == "true limited") or (not held.right and w.vx < 1.5) or frames > 200
  local jump = 0
  for i = 3, #speeds do
    jump = math.max(jump, math.abs((speeds[i - 1] - speeds[i]) - (speeds[i - 2] - speeds[i - 1])))
  end
  if held.right then
    check("right held: a long glide back to the heli's top speed and normal flight in 76 frames, despite the wind",
      frames == 76 and near(w.vx, 5), frames .. " " .. w.vx)
  else
    check("no key: a long glide, slowing evenly, below 1.5 in 2 seconds despite the wind",
      frames > 80 and frames < 100 and jump < 0.13, frames .. " frames, slowing changed by " .. jump)
  end
end

print("helicopter dash: the option's fuel, steering on the coast")
do
  local w = new_match({ dash_fuel = 100 })
  take_off(w)
  shift, w.keys = true, { right = true }
  frame(w, 15)
  check("the option's 100 is 10 units: 15 frames of dash", w.gravity == 0)
  frame(w)
  check("then it ends", w.gravity == 0.2)

  w = new_match()
  take_off(w)
  shift, w.keys = true, { right = true }
  frame(w, 20)
  shift, w.keys = false, {}
  frame(w)
  w.keys = { up = true }
  frame(w)
  check("coasting, the arrows steer at the dash's 50%: half the heli's 0.8 push",
    near(w.vy, -0.4) and w.vx > 5, w.vy .. ", " .. w.vx)
  w.keys = {}
  while w.vx > 5 do frame(w) end
  frame(w)
  w.vy, w.keys = 0, { up = true }
  frame(w)
  check("down to its own top speed, they steer at 100% again", near(w.vy, -0.8), w.vy)
end

print("helicopter acceleration: the option scales the arrows' push, not the top speed")
for _, case in ipairs({ { 100, 9 }, { 200, 4 }, { 50, 22 } }) do
  local w = new_match({ acceleration = case[1] })
  take_off(w)
  w.keys = { right = true }
  local frames = 0
  repeat
    frame(w)
    w.vx = math.min(w.vx, 5) -- WA's Maximum Jet Pack Speed, which the mock leaves out
    frames = frames + 1
  until w.vx >= 5 or frames > 100
  check(case[1] .. "%: top speed in " .. case[2] .. " frames", frames == case[2], frames)
end
do
  local w = new_match({ acceleration = 200 })
  take_off(w)
  shift, w.keys = true, { right = true }
  frame(w, 20)
  shift, w.keys = false, {}
  frame(w)
  w.keys = { up = true }
  frame(w)
  check("200%: the coast's 50% steering doubles too", near(w.vy, -0.8), w.vy)
end

print("helicopter fuel: infinite counts up from 0, as WA's infinite jet pack does")
do
  local w = new_match({ fuel = 0 })
  take_off(w)
  check("the counter starts at 0", w.fuel < 0.03, w.fuel)
  local start = w.fuel
  frame(w)
  check("idle: the counter goes up by what a limited heli burns", near(w.fuel - start, 0.02), w.fuel - start)
  w.keys = { up = true, right = true }
  local before = w.fuel
  frame(w)
  check("up and right: 0.32 more", near(w.fuel - before, 0.32), w.fuel - before)
  w.keys = {}
  frame(w, 2000)
  check("it never runs out: still flying, no crash", w.gravity == 0.2 and #booms == 0 and w.fuel > 40, w.fuel)

  w = new_match({ fuel = 1 })
  take_off(w)
  frame(w, 60)
  check("limited fuel still runs out and crashes", #booms > 0)
end

print("helicopter crash: its size grows with speed only as far as the option says")
for _, case in ipairs({ { 0, 10 }, { 50, 17 }, { 100, 24 } }) do
  local w = new_match({ crash_speed_scale = case[1] })
  take_off(w)
  w.vx, w.y = 20, 20000 -- 10 a frame by the crash's measure, into the water
  frame(w)
  local blast = booms[#booms]
  check("scale " .. case[1] .. "%: size " .. case[2], blast and blast.id == case[2] and blast.damage == 2 * case[2],
    blast and blast.id)
end

print("helicopter dash: no arrow, the way the heli moves or faces; leftover speed fades")
do
  local w = new_match()
  take_off(w)
  w.vx, w.vy, w.keys = 3, -1, {}
  shift = true
  frame(w, 5)
  check("moving at an angle: it keeps that angle, the heli's nose into it",
    near(w.vx / w.vy, -3) and math.abs(spawned[#spawned].angle - math.deg(math.atan(-1, 3)) % 360) < 1e-6,
    spawned[#spawned].angle)

  w = new_match()
  take_off(w)
  w.vx, w.vy, w.facing, w.keys = 0, 0.2, -1, {}
  shift = true
  frame(w)
  check("nearly still: the way the heli faces", w.vx < 0 and near(w.vy, 0), w.vx .. "," .. w.vy)

  -- the 2026-11-25 match, frame 1146: Up held, still drifting left from a dash before
  w = new_match()
  take_off(w)
  w.vx, w.vy, w.keys = -2.155, -4.952, { up = true }
  shift = true
  frame(w, 20)
  local ex, ey = dash_frames(-2.155, -4.952, w.keys, 20)
  check("Up alone: the leftover sideways speed fades as in normal flight, the heli climbing",
    near(w.vx, ex) and near(w.vy, ey) and math.abs(w.vx) < 0.8 and w.vy < -12, w.vx .. "," .. w.vy)
end

print("helicopter dash: 10000%")
do
  local w = new_match({ dash_speed = 10000 })
  take_off(w)
  shift, w.keys = true, { right = true }
  local frames = 0
  repeat frame(w); frames = frames + 1 until w.vx >= 500 or frames > 100
  check("100 times the heli's top speed, in half a second", near(w.vx, 500) and frames == 22, frames)
  shift = false
  frame(w)
  check("the coast slows it without turning it round", w.vx > 0 and w.vx < 500, w.vx)
end

print("helicopter dash: no fresh press, vertical, the dash turned off")
do
  local w = new_match()
  shift = true
  take_off(w)
  frame(w)
  check("Shift held from the take-off doesn't dash", w.gravity == 0.2)
  shift = false
  frame(w)
  w.keys = { up = true, left = true, right = true }
  w.facing = -1
  shift = true
  frame(w)
  frame(w, 5)
  local _, ey = dash_frames(0, 0, w.keys, 6)
  check("left and right cancel: straight up, the facing kept",
    near(w.vx, 0) and near(w.vy, ey) and w.facing == -1 and spawned[#spawned].angle == 90, spawned[#spawned].angle)
  shift = false
  frame(w)
  check("letting Shift go ends the dash", w.gravity == 0.2)

  w = new_match({ dash_fuel = 0 })
  take_off(w)
  shift = true
  w.keys = { right = true }
  frame(w)
  check("dash fuel 0: no dash, no bar and no tooltip",
    w.gravity == 0.2 and #sheets(draw(), BAR) == 0 and hints["px.helicopter"](w) == nil)
end

print("helicopter dash: each press costs part of the bar, and a dry bar waits until it's full")
do
  local w = new_match({ dash_fuel = 100, dash_use_cost = 15 })
  take_off(w)
  shift, w.keys = true, { right = true }
  frame(w)
  local bars = sheets(draw(), BAR)
  check("a press takes 15% of the bar, then the dash burns its frame",
    w.gravity == 0 and near(width(bars[2]), 40 * (15 - 2.25 - 1) / 15), width(bars[2]))
  shift = false
  frame(w)
  shift = true
  frame(w)
  check("a part-filled bar dashes again", w.gravity == 0)
  local taps = 2
  repeat
    shift = false
    frame(w)
    shift = true
    frame(w)
    taps = taps + 1
  until sheets(draw(), FRAME)[1].color == 0xFFFF7070 or taps > 20
  check("tapping on runs it dry: 5 taps, then the outline turns red", taps == 5 and #pops == 0, taps)
  shift = false
  frame(w)
  shift = true
  frame(w)
  check("dry: Shift doesn't dash", w.gravity == 0.2, w.gravity)
  shift = false
  local waited = 0
  while #pops == 0 and waited < 1000 do frame(w); waited = waited + 1 end
  check("full again: the crate pop, once", #pops == 1 and sheets(draw(), FRAME)[1].color == 0xFFFFFFFF, waited)
  shift = true
  frame(w)
  check("and it dashes again", w.gravity == 0)
end

print("ALL PASS")
