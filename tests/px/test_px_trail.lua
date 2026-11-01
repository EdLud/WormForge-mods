-- lua mods/tests/px/test_px_trail.lua
-- With wa.draw.trail, lib/px_trail.lua hands each round's trail to the
-- engine: the same ramp settings, a point per sampled frame, finished once
-- the round is gone, and no wa.on.draw of its own.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../px/"
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok)
  print((ok and "  ok   " or "  FAIL ") .. name)
  if not ok then failed = failed + 1 end
end

local kept, draws, missile_frames, driver = {}, {}, {}, nil
wa = {
  depth = { OBJECTS = 0xE0000 },
  on = {
    missile_frame = function(f) missile_frames[#missile_frames + 1] = f end,
    draw = function(f) draws[#draws + 1] = f end,
  },
  draw = {
    ribbon = function() error("drawn by the engine, not wa.draw.ribbon") end,
    trail = function(spec)
      local t = { spec = spec, pushed = {}, finished = false }
      function t:push(x, y) self.pushed[#self.pushed + 1] = { x, y } end
      function t:finish() self.finished = true end
      kept[#kept + 1] = t
      return t
    end,
  },
  sprites = { key = function(path) return "px.attack_helicopter:" .. path end },
  actors = {
    spawn = function(spec)
      driver = { on = spec.on, gone = false }
      function driver:despawn() self.gone = true end
      return driver
    end,
  },
}

local trail = dofile(root .. "lib/px_trail.lua")
trail.install()
check("no draw hook: the engine draws the trails", #draws == 0)

local t = trail.add(77, "owner", { g = 30, b = 10 })
local spec = kept[1] and kept[1].spec or {}
check("one kept trail per round", #kept == 1 and t.kept == kept[1])
check("PX's ramp settings", spec.width == trail.CORE_W and spec.glow_width == trail.GLOW_W
  and spec.max == trail.MAX and spec.shed == trail.VANISH and spec.floor == 0.1 and spec.blend == "add")
check("its colour", spec.color == 0xFFFF1E0A)
check("sheets by key", spec.sprite == "px.attack_helicopter:" .. trail.BEAM
  and spec.glow == "px.attack_helicopter:" .. trail.GLOW)
check("depth resolved in a game frame", spec.depth == wa.depth.OBJECTS)

-- The round flies: a frame each game frame, sampled every `every` (2).
local function frame(x)
  for _, f in ipairs(missile_frames) do
    f({ id = 77, phase = "pre", x = x, y = 5, vx = 3, vy = 0 })
    f({ id = 77, phase = "post", x = x, y = 5, vx = 3, vy = 0 })
  end
  driver.on(driver)
end
for x = 1, 8 do frame(x * 3) end
local same = #kept[1].pushed == #t.pts
for i, p in ipairs(t.pts) do same = same and kept[1].pushed[i][1] == p[1] and kept[1].pushed[i][2] == p[2] end
check("a point every second frame, as the module samples", #kept[1].pushed == 4 and same)
check("not finished while the round flies", not kept[1].finished and trail.has(77))

-- The round is gone: no more frames.
for _ = 1, 3 do driver.on(driver) end
check("finished once its round stopped", kept[1].finished and not trail.has(77))
check("handed over: the driver goes", driver.gone)

local u = trail.add(78, "owner")
trail.drop(78)
check("drop finishes at once", kept[2].finished and kept[2].spec.glow ~= nil)

if failed > 0 then error(failed .. " failed") end
print("ALL PASS")
