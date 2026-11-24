-- lua mods/tests/px/test_helicopter.lua
-- Helicopter Dash: Shift locks one of eight directions and ramps to dash speed,
-- then the heli coasts on; the other arrows steer across it, the fuel drains and refills, the bar draws.
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

local handlers, draws, quads, ribbons, spawned, worms, shift, pops

local function new_match(options)
  handlers, draws, quads, ribbons, spawned, worms, shift, pops = {}, {}, {}, {}, {}, {}, false, {}
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
    math = { sin = math.sin },
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
      keys = function() return { shift = shift } end,
      water = function() return 10000 end,
      retreat = function() return 0 end,
      frame = function() return 0 end,
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
  local values = { fuel = 100, dash_fuel = 1000, dash_speed = 300, dash_steer_factor = 50, dash_refill_factor = 30,
    crash_speed_scale = 0 }
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
  local d = 0.70710678118654752
  check("Shift with up and right: up-right, ramping from a standstill, no gravity or wind",
    near(w.vx, 1.5) and near(w.vy, -1.5) and w.gravity == 0 and w.wind == 0, w.vx .. "," .. w.vy)
  frame(w)
  check("the heli turns to the dash, 30 degrees a frame", body.angle == 315, body.angle)
  w.keys = {}
  frame(w, 7)
  check("9 frames in: not yet at dash speed", near(w.vx, 13.5))
  frame(w)
  check("300% of the heli's top speed that way (5 an axis), reached in 200 ms",
    near(w.vx, 15) and near(w.vy, -15) and w.steer == "true unlimited", w.steer)
  frame(w, 5)
  check("then the direction and speed stay locked", near(w.vx, 15) and near(w.vy, -15))

  w.keys = { down = true }
  frame(w)
  local across = 0.4 * d
  check("down steers across the dash at half the heli's push",
    near(w.vx, 15 + across) and near(w.vy, -15 + across), w.vx .. "," .. w.vy)
  w.keys = { up = true, right = true }
  frame(w)
  check("the dash's own keys don't steer: the sideways speed eases off",
    near(w.vx - 15, across / 1.105) and near(w.vy + 15, across / 1.105))

  bars = sheets(draw(), BAR)
  local lines = sheets(ribbons, LINE)
  check("dashing: the fill turns red and glows, streaks of air flow round the heli",
    bars[2].color == 0xFFFE6A5A and #sheets(quads, GLOW) == 1 and #lines > 20 and #lines == #ribbons
    and lines[1].n == 5, #lines)
  local dashing, dashing_count = strongest(), #ribbons

  w.keys = {}
  frame(w, 133)
  check("1000 fuel (100 units) lasts 150 frames", w.gravity == 0, w.gravity)
  frame(w)
  check("empty: the dash ends, the heli's gravity and wind back", w.gravity == 0.2 and w.wind == 0.2)
  local vx, vy = w.vx, w.vy
  frame(w)
  local drag = 1 / (1 + 0.0015 * math.sqrt(vx * vx + vy * vy))
  check("then it coasts, air drag slowing it by the square of its speed",
    near(w.vx, vx * drag) and near(w.vy, vy * drag), w.vx)
  frame(w, 20)
  check("still holding Shift starts no new dash", w.gravity == 0.2)
  check("22 frames on it's still faster than the heli flies, the limit still lifted",
    math.abs(w.vx) > 5 and w.steer == "true unlimited", w.vx)
  draw()
  check("and the air lines thin out with it: fewer and fainter", #ribbons > 0 and #ribbons < dashing_count
    and strongest() < dashing, #ribbons .. " < " .. dashing_count .. ", " .. strongest() .. " < " .. dashing)

  shift = false
  frame(w, 49)
  bars = sheets(draw(), BAR)
  check("the refill runs from the dash's end at 30% of the burn: 71 frames, 14.2 fuel",
    near(width(bars[2]), 40 * 0.3 * 71 / 150), width(bars[2]))
  check("slowed to the heli's own speed, the coast is over and the limit back",
    math.abs(w.vx) <= 5 and math.abs(w.vy) <= 5 and strongest() == 0 and w.steer == "true limited", w.steer)
  shift = true
  frame(w)
  check("a part-filled bar doesn't dash", w.gravity == 0.2 and #pops == 0)
  shift = false
  local waited = 0
  while #pops == 0 and waited < 1000 do frame(w); waited = waited + 1 end
  check("full again after 128.7 more frames: the crate pop, an octave up",
    waited == 429 and pops[1] == 12, waited .. " frames, pitch " .. tostring(pops[1]))
  frame(w, 10)
  check("once", #pops == 1)
  w.vx, w.vy = -4, 3
  shift = true
  w.facing = -1
  frame(w)
  check("Shift with no arrows dashes the way the heli faces, from its speed that way",
    near(w.vx, -5.5) and near(w.vy, 3 / 1.105), w.vx .. "," .. w.vy)
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

print("helicopter crash: its size grows with speed only as far as the option says")
for _, case in ipairs({ { 0, 10 }, { 50, 17 }, { 100, 24 } }) do
  local w = new_match({ crash_speed_scale = case[1] })
  take_off(w)
  w.vx, w.y = 20, 20000 -- 10 a frame by the crash's measure, into the water
  frame(w)
  local blast = spawned[#spawned].explode
  check("scale " .. case[1] .. "%: size " .. case[2], blast and blast.id == case[2] and blast.damage == 2 * case[2],
    blast and blast.id)
end

print("helicopter dash: 10000%")
do
  local w = new_match({ dash_speed = 10000 })
  take_off(w)
  shift, w.keys = true, { right = true }
  frame(w, 10)
  check("100 times the heli's top speed, in 200 ms", near(w.vx, 500))
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
  check("left and right cancel: straight up, the facing kept",
    w.vx == 0 and near(w.vy, -9) and w.facing == -1 and spawned[#spawned].angle == 90, spawned[#spawned].angle)
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

print("ALL PASS")
