-- lua mods/tests/px/test_wings.lua
-- Wings: WA's parachute flies the worm without gravity; the wings fold where
-- WA would pack its parachute away.
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local handlers, turn_ends, sounds, spawned
package.loaded["wf-lib/own_time"] = { frames = function() return 1 end }

local function check(what, ok, detail)
  if not ok then error("FAIL: " .. what .. (detail and ("   [" .. tostring(detail) .. "]") or ""), 2) end
  print("  ok   " .. what)
end

local worms
local function new_match()
  handlers, turn_ends, sounds, spawned, worms = {}, {}, {}, {}, {}
  wa = {
    depth = { WORMS = 0xD0000 },
    msg = { FRAME_FINISH = 2, WEAPON_RELEASED = 0x49 },
    on = {
      worm_message = function(f, filter)
        local wants = {}
        for _, m in ipairs(filter.msgs) do wants[m] = true end
        handlers[#handlers + 1] = { f = f, wants = wants }
      end,
      turn_end = function(f) turn_ends[#turn_ends + 1] = f end,
    },
    sound = { play = function(_, path) sounds[#sounds + 1] = path end },
    actors = {
      spawn = function(spec)
        local a = { sprite = spec.sprite, x = spec.x, y = spec.y }
        function a:gfx(g) for k, v in pairs(g) do self[k] = v end end
        function a:frame(i) self.shown = i end
        function a:remove() self.dead = true end
        spawned[#spawned + 1] = a
        return a
      end,
    },
    worms = { all = function() return worms end },
  }
  package.loaded["lib/parachute"] = nil
  dofile(root .. "weapons/wings.lua").setup()
  local w = { id = 17, x = 100, y = 50, vx = 0, vy = 3, facing = 1, gravity = 1, state = "jumping",
    weapon = "px.wings", body_visible = true, keys = {} }
  worms[1] = w
  return w
end

local function message(w, msg)
  for _, h in ipairs(handlers) do
    if h.wants[msg] then h.f(w, msg) end
  end
end

-- WA's fire of a parachute, then where WA has the worm by the pack's next frame.
local function wa_fires(w, state_after)
  w.state = "parachuting"
  message(w, wa.msg.WEAPON_RELEASED)
  w.state = state_after or "parachuting"
  message(w, wa.msg.FRAME_FINISH)
end

print("wings: flight on WA's parachute")
do
  local w = new_match()
  w.gravity = 0.85 -- a Small Worm's
  message(w, wa.msg.FRAME_FINISH)
  check("nothing before WA fires it", #spawned == 0 and w.gravity == 0.85)
  wa_fires(w)
  local fly = spawned[1]
  check("opened: no gravity, the flap, the wings drawn in the worm's place",
    w.gravity == 0 and sounds[1] == "sounds/wings/flap.wav" and fly.sprite == "sprites/wings/fly.png"
    and fly.glow_of == w and fly.follow == w and w.body_visible == false)
  w.keys = { left = true }
  message(w, wa.msg.FRAME_FINISH)
  check("left turns the worm left, its art mirrored", w.facing == -1 and fly.facing == 1)
  w.keys = { right = true }
  message(w, wa.msg.FRAME_FINISH)
  check("right turns it right", w.facing == 1 and fly.facing == -1)
  w.keys = {}
  local shown = {}
  for _ = 1, 13 do
    message(w, wa.msg.FRAME_FINISH)
    shown[#shown + 1] = fly.shown
  end
  check("the wings flap: 10 frames at 40 a second, round and round",
    table.concat(shown, ",") == "2,3,4,4,5,6,7,8,8,9,0,1,2", table.concat(shown, ","))
  -- WA lands it: its parachute's pack-away is drawn over by the wings folding.
  w.state = "jump_falling"
  message(w, wa.msg.FRAME_FINISH)
  local fold = spawned[2]
  check("landed: gravity back as it was, the wings fold", w.gravity == 0.85 and fly.dead
    and fold.sprite == "sprites/wings/fold.png" and fold.shown == 0 and w.body_visible == false)
  for _ = 1, 11 do message(w, wa.msg.FRAME_FINISH) end
  check("the fold runs at 24 frames a second", fold.shown == 5 and not fold.dead, fold.shown)
  check("and holds until WA stands the worm up", w.body_visible == false)
  w.state = "standing"
  message(w, wa.msg.FRAME_FINISH)
  message(w, wa.msg.FRAME_FINISH)
  check("standing after the fold: the worm shown again", fold.dead and w.body_visible == true)
end

print("wings: WA opens and lands them at once on a hard landing")
do
  local w = new_match()
  message(w, wa.msg.FRAME_FINISH)
  wa_fires(w, "jump_falling")
  local fold = spawned[1]
  check("no flight: gravity left alone, the flap, the wings fold", w.gravity == 1
    and sounds[1] == "sounds/wings/flap.wav" and fold.sprite == "sprites/wings/fold.png" and #spawned == 1)
end

print("wings: closed in the air, the turn's end, another weapon")
do
  local w = new_match()
  wa_fires(w)
  w.state = "falling" -- the jump key closed WA's parachute
  message(w, wa.msg.FRAME_FINISH)
  check("closed in the air: gravity back, no fold, the worm shown", w.gravity == 1 and spawned[1].dead
    and #spawned == 1 and w.body_visible == true)

  w = new_match()
  wa_fires(w)
  for _, f in ipairs(turn_ends) do f({}) end
  check("the turn's end gives gravity back, the wings still out", w.gravity == 1 and not spawned[1].dead)
  w.gravity = 0.5
  w.state = "jump_falling"
  message(w, wa.msg.FRAME_FINISH)
  check("given back once only", w.gravity == 0.5 and spawned[2].sprite == "sprites/wings/fold.png")

  w = new_match()
  w.weapon = "px.hang_glider"
  wa_fires(w)
  check("another parachute's fire is not the wings'", #spawned == 0 and w.gravity == 1 and #sounds == 0)
end

print("ALL PASS")
