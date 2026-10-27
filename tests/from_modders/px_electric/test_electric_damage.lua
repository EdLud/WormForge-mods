-- Plain Lua harness for lib/electric_damage.lua. Run from anywhere:
--   lua tests/from_modders/px_electric/test_electric_damage.lua
-- No WA needed; the fake wa records calls the way the engine would.
local PACK_ROOT = (arg[0]:match("^(.*[/\\])") or "") .. "../../../from_modders/px_electric/"
local path = arg[1] or PACK_ROOT .. "lib/electric_damage.lua"

local function setup()
  local frame = 10
  local hooks, quads, sounds, actor = {}, {}, {}, nil
  local wa = {
    depth = { BEHIND_TERRAIN = 0x80000, WORMS = 0xD0000 },
    msg = { FRAME_FINISH = 2 },
    sprites = { key = function(p) return "px:" .. p end },
    sound = { play = function(_, p) sounds[#sounds + 1] = p end },
    on = setmetatable({}, { __index = function(_, name)
      return function(cb, o)
        hooks[name] = cb
        hooks[name .. "_opts"] = o
      end
    end }),
    actors = { spawn = function(spec) actor = spec; return {} end },
    world = { frame = function() return frame end },
    worms = { all = function() return {} end },
    draw = {
      random = function() return 0.5 end,
      quad = function(q)
        quads[#quads + 1] = { sprite = q.sprite, frame = q.frame,
          blend = q.blend, color = q.color }
      end,
    },
    log = function() end,
  }
  local env = setmetatable({ wa = wa }, { __index = _G })
  local M = assert(loadfile(path, "t", env))()
  local w = {
    id = 17, x = 100, y = 200, vx = 0, vy = 0, hp = 100,
    taken = false, body_visible = true, hurts = 0,
  }
  function w:take(o) self.taken = true; self.take_opts = o end
  function w:release(vx, vy, opts) self.taken = false; self.vx = vx; self.vy = vy; self.release_opts = opts end
  function w:hurt(n) self.hp = self.hp - n; self.hurts = self.hurts + 1 end
  -- The frame observer spawns on the first FRAME_FINISH.
  hooks.worm_message(w, 2)
  assert(actor and actor.on, "the frame observer was not spawned")
  local e = {
    M = M, wa = wa, worm = w, sounds = sounds,
    tick = function(n) for _ = 1, n do actor.on() end end,
    hurt = function(hit)
      hit.worm = hit.worm or w
      hit.hp = hit.hp or w.hp
      hooks.hurt(hit)
    end,
    draw = function()
      quads = {}
      hooks.draw()
      return quads
    end,
    set_frame = function(f) frame = f end,
  }
  return e
end

-- Direct: hold, then damage and push.
local a = setup()
a.M.hurt_electric(a.worm, 24, { frames = 3, push_x = 1, push_y = -4 })
assert(a.worm.taken and not a.worm.body_visible, "taken and hidden")
assert(a.worm.vx == 0 and a.worm.vy == 0, "stopped")
assert(a.worm.take_opts and a.worm.take_opts.turn == "freeze", "turn frozen")
assert(a.sounds[1] == "wf-lib/electric/sounds/lightning/tazer_loop.wav", "loop sound")
local q = a.draw()
assert(#q == 2, "pose and glow")
assert(q[1].sprite:find("tazed"), "tazed sheet")
assert(q[1].blend == "alpha" and q[2].blend == "add", "blends")
a.tick(2)
assert(a.worm.taken and a.worm.hp == 100, "damage waits for the hold")
a.tick(1)
assert(not a.worm.taken and a.worm.body_visible, "released and shown")
assert(a.worm.hp == 76 and a.worm.hurts == 1, "damage applied once")
assert(a.worm.vx == 1 and a.worm.vy == -4, "push applied")
assert(a.worm.release_opts and a.worm.release_opts.tumble, "tumble release")

-- Another component overwrites wa.sprites.key after load; the draw passes the
-- pack-relative path, which the hook wrapper resolves under this pack.
local k = setup()
k.wa.sprites.key = function(p) return "other:" .. p end
k.M.taze(k.worm, { frames = 2 })
assert(k.draw()[1].sprite:find("^wf%-lib/electric/sprites/electric_grenade/tazed"),
  "the pose is drawn by its path")

-- WA can release or re-show the worm mid-hold; the tick restores the pose.
local a2 = setup()
a2.M.hurt_electric(a2.worm, 0, { frames = 3 })
a2.worm.taken = false
a2.worm.body_visible = true
a2.tick(1)
assert(a2.worm.taken and not a2.worm.body_visible, "the hold is restored")
a2.tick(2)
assert(not a2.worm.taken and a2.worm.body_visible, "released after the hold")

-- A long hold repeats the loop, as electrical.lua does every 46 frames.
local a3 = setup()
a3.M.hurt_electric(a3.worm, 0, { frames = 47 })
a3.tick(46)
assert(#a3.sounds == 2, "the loop repeats")

-- Armed hit: the hit's damage is not repeated, only the hold is added.
local b = setup()
b.M.set_message_electric(4, 2, -3, false)
b.hurt({ phase = "pre", kind = "hit", lost = 0 })
assert(not b.worm.taken, "pre does nothing")
b.hurt({ phase = "post", kind = "hit", lost = 10 })
assert(b.worm.taken and not b.worm.body_visible, "armed hit tazes")
assert(b.worm.hp == 100, "the library adds no damage")
b.tick(4)
assert(not b.worm.taken and b.worm.hp == 100, "released with no extra damage")
assert(b.worm.vx == 2 and b.worm.vy == -3, "armed push")

-- The 8-frame window: a hit after it is a normal hit.
local c = setup()
c.M.set_message_electric(4, 0, -3, false)
c.set_frame(19)
c.hurt({ phase = "post", kind = "hit", lost = 10 })
assert(not c.worm.taken, "expired arm does not taze")

-- retain_speed keeps what the hit gave the worm.
local d = setup()
d.worm.vx, d.worm.vy = 3, -5
d.M.set_message_electric(2, 0, -4, true)
d.hurt({ phase = "post", kind = "hit", lost = 10 })
assert(d.worm.vx == 0 and d.worm.vy == 0, "stopped during the hold")
d.tick(2)
assert(d.worm.vx == 3 and d.worm.vy == -5, "retained the hit's speed")

-- Explosions keep the blast's speed too.
local e = setup()
e.worm.vx, e.worm.vy = -2, -6
e.M.set_message_electric_missile(2)
e.hurt({ phase = "post", kind = "blast", lost = 15 })
assert(e.worm.taken, "blast tazes")
e.tick(2)
assert(e.worm.vx == -2 and e.worm.vy == -6, "blast speed retained")

-- owner narrows a missile arm to that worm's blasts.
local j = setup()
j.M.set_message_electric_missile(2, { id = 99 })
j.hurt({ phase = "post", kind = "blast", lost = 10, attacker = { id = 1 } })
assert(not j.worm.taken, "another worm's blast")
j.hurt({ phase = "post", kind = "blast", lost = 10, attacker = { id = 99 } })
assert(j.worm.taken, "the owner's blast")

-- A second link extends the hold and adds its damage.
local f = setup()
f.M.hurt_electric(f.worm, 10, { frames = 4 })
f.M.hurt_electric(f.worm, 5, { frames = 2 })
f.tick(4)
assert(f.worm.hp == 85 and f.worm.hurts == 1, "chained damage commits once")

-- A worm killed while held keeps the pose to the end of the hold, then is let
-- go without the library's damage.
local g = setup()
g.M.hurt_electric(g.worm, 10, { frames = 4 })
g.worm.hp = 0
g.tick(1)
assert(g.worm.taken and not g.worm.body_visible, "still held after the hit")
g.tick(3)
assert(not g.worm.taken and g.worm.body_visible, "released when the hold ends")
assert(g.worm.hurts == 0, "no damage on a dead worm")

-- The hold is not gated by HP: a worm already at 0 is still taken, drawn, and
-- released with its push (`worm:release` carries it; `worm:hurt` does not).
local n = setup()
n.worm.hp = 0
n.M.taze(n.worm, { frames = 2, push_x = 3, push_y = -5 })
assert(n.worm.taken and not n.worm.body_visible, "a dead worm is still held")
assert(n.draw()[1].sprite:find("tazed"), "its pose still draws")
n.tick(2)
assert(not n.worm.taken and n.worm.body_visible, "released after the hold")
assert(n.worm.vx == 3 and n.worm.vy == -5, "the dead worm gets the push")

-- A lethal hit lands, and the library still writes no push to a dead worm.
local h = setup()
h.worm.hp = 10
h.M.hurt_electric(h.worm, 10, { frames = 1 })
h.tick(1)
assert(h.worm.hp == 0 and h.worm.hurts == 1, "lethal damage applied")

-- draw/sound are optional for a caller that has its own pose.
local i = setup()
i.M.taze(i.worm, { frames = 2, draw = false, sound = false })
assert(#i.draw() == 0 and #i.sounds == 0, "pose and sound suppressed")

print("electric_damage: direct, armed hit, window, retain, blast, chain, death and options passed")
