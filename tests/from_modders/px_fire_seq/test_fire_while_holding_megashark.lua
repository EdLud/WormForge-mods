-- Plain Lua harness for the hold-to-fire Megashark's on_fire, ammo write and
-- Space gate. The real sequencer is covered by test_fire_seq_cancel.lua; this
-- stubs it so the weapon's choices can be checked without an engine.
--   lua tests/from_modders/px_fire_seq/test_fire_while_holding_megashark.lua
local PACK_ROOT = (arg[0]:match("^(.*[/\\])") or "") .. "../../../from_modders/px_fire_seq/"
local frames, cancel = {}, {}

package.loaded["lib/px_sprite_builder"] = { PX_POSTURE = {} }
package.loaded["wf-lib/effects/trail"] = {
  BEAM = "beam", GLOW = "glow",
  install = function() end,
  add = function() end,
  sample = function() end,
  drop = function() end,
}
package.loaded["lib/px_hold_art"] = { add = function() end }
package.loaded["lib/fire_seq"] = {
  fire_sequential_actor = function(opts)
    frames[#frames + 1] = opts
    return { fake = true }
  end,
  cancel = function(worm)
    cancel[#cancel + 1] = worm.id
    return true
  end,
}

local spec, handler
local keys = { space = true }
_G.wa = {
  on = {
    worm_message = function(fn, opts)
      assert(opts.msgs[1] == 77)
      handler = fn
    end,
  },
  msg = { FRAME_FINISH = 77 },
  math = math,
  actors = { spawn = function() error("no actors in this harness") end },
  weapons = { replace = function(s) spec = s end },
  sound = { play = function() end },
  world = { keys = function() return keys end },
}

local M = assert(loadfile(PACK_ROOT .. "weapons/fire_while_holding_megashark.lua"))()
M.install({ id = "px.megashark_hold", weapons = { ["px.megashark_hold"] = true } })
assert(spec and spec.on_fire, "the weapon registers")
assert(handler, "the Space gate registers")

local function worm(ammo)
  return {
    id = 1, hp = 100, x = 100, y = 200, turn = true,
    weapon = "px.megashark_hold", ammo_value = ammo,
    ammo = function(self, id, change)
      assert(id == "px.megashark_hold")
      if change then self.ammo_value = change.set end
      return self.ammo_value
    end,
  }
end

local w = worm(-1)
keys.space = true
spec.on_fire({ worm = w, x = 102, y = 197, vx = 0, vy = -30 })
assert(frames[1].count == 20, "infinite ammo caps at 20")
assert(frames[1].cancel_weapon == "px.megashark_hold", "the burst checks its own slot")

-- Release: the handler cancels the running burst exactly once.
keys.space = false
handler(w)
assert(cancel[1] == 1, "releasing Space cancels the burst")
handler(w)
assert(#cancel == 1, "a cleared hold does not cancel again")

-- A finite stock is written back from the fired count.
frames = {}
w = worm(50)
keys.space = true
spec.on_fire({ worm = w, x = 102, y = 197, vx = 0, vy = -30 })
assert(frames[1].count == 20, "a large finite stock caps at 20")
frames[1].on_done(w, 20)
assert(w.ammo_value == 30, "20 of 50 left, absolute write")

frames = {}
w = worm(5)
spec.on_fire({ worm = w, x = 102, y = 197, vx = 0, vy = -30 })
assert(frames[1].count == 5, "a short stock fires every bullet")
frames[1].on_done(w, 3)
assert(w.ammo_value == 2, "a cancelled burst writes only the shots that left")

-- Infinite is never written down.
frames = {}
w = worm(-1)
spec.on_fire({ worm = w, x = 102, y = 197, vx = 0, vy = -30 })
frames[1].on_done(w, 7)
assert(w.ammo_value == -1, "infinite ammo stays infinite")

print("fire_while_holding_megashark: cap, Space gate and absolute ammo write passed")
