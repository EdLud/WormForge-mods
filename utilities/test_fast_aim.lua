-- From the repository root: lua mods/utilities/test_fast_aim.lua
local root = UTILITIES_ROOT or "mods/utilities/"

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

-- WA's worm, its aim target +0x24C as raw 0..0x10000, and control_aim
-- (0x51D100) run after the Lua handler each frame: the step, the weapon's
-- limits, and the round down to the 0x200 grid.
local handler, shift
local function setup(pct)
  shift = true
  wa = {
    world = { keys = function() return { shift = shift } end },
    msg = { FRAME_FINISH = 2 },
    on = { worm_message = function(f) handler = f end },
    log = function() end,
  }
  dofile(root .. "features/fast_aim.lua")(pct)
end

local function worm(raw)
  local w = { id = 1, turn = true, aiming = true, raw = raw or 0x8000, writes = 0 }
  return setmetatable(w, { __index = function(t, k)
    if k == "aim_target" then return t.raw * 180 / 65536 - 90 end
    if k == "input" then
      return function(self, spec)
        self.raw = math.floor((spec.aim + 90) * 65536 / 180 + 0.5)
        self.writes = self.writes + 1
      end
    end
  end })
end

local function frames(w, n, key, opts)
  opts = opts or {}
  local lo, hi, step = opts.lo or 0, opts.hi or 0x10000, opts.step or 0x200
  for i = 1, n do
    if not opts.after then handler(w) end
    if step == 0x200 then
      if key == "up" then w.raw = w.raw + 0x200 end
      if key == "down" then w.raw = w.raw - 0x200 end
      w.raw = math.max(lo, math.min(hi, w.raw))
      w.raw = (w.raw // 0x200) * 0x200
    elseif i % 16 == 0 then
      -- A coarse aim: 0x4000 every 16 frames, rounded to that grid.
      w.raw = w.raw + (key == "up" and step or -step)
      w.raw = math.max(lo, math.min(hi, ((w.raw + step // 2) // step) * step))
    end
    if opts.after then handler(w) end
  end
end

-- Native speed without Shift: 0x200 a frame.
setup(200)
shift = false
local w = worm(0x4000)
frames(w, 20, "up")
check("no Shift keeps WA's speed", w.raw == 0x4000 + 20 * 0x200, w.raw)
check("no Shift writes nothing", w.writes == 0, w.writes)

-- 200%: after the first two frames (the start and the first step taken
-- on) every step counts twice.
for _, case in ipairs({ { 200, "up", 1 }, { 200, "down", -1 }, { 400, "up", 1 }, { 300, "down", -1 } }) do
  local pct, key, sign = case[1], case[2], case[3]
  setup(pct)
  w = worm(0x8000)
  frames(w, 2, key)
  local start = w.raw
  frames(w, 10, key)
  check(pct .. "% " .. key, w.raw - start == sign * 10 * 0x200 * pct // 100, (w.raw - start) / 0x200)
end

-- The same with WA's step before the handler in the frame.
setup(300)
w = worm(0x8000)
frames(w, 2, "up", { after = true })
local start = w.raw
frames(w, 10, "up", { after = true })
check("300% up, handler after WA", w.raw - start == 30 * 0x200, (w.raw - start) / 0x200)
setup(50)
w = worm(0x8000)
frames(w, 2, "down", { after = true })
start = w.raw
frames(w, 20, "down", { after = true })
check("50% down, handler after WA", start - w.raw == 10 * 0x200, (start - w.raw) / 0x200)

-- Slower: 50% every other step, 1% one step in a hundred.
setup(50)
w = worm(0x4000)
frames(w, 2, "up")
start = w.raw
frames(w, 20, "up")
check("50% is half", w.raw - start == 10 * 0x200, (w.raw - start) / 0x200)
setup(1)
w = worm(0x4000)
frames(w, 2, "up")
start = w.raw
frames(w, 200, "up")
check("1% is one step in a hundred", w.raw - start == 2 * 0x200, (w.raw - start) / 0x200)

-- A weapon's limit (aiming only from level up): pushed past it, WA clamps
-- back, and the aim stays at the limit, then turns up at full speed.
setup(400)
w = worm(0x9000)
local lowest = w.raw
for _ = 1, 40 do
  frames(w, 1, "down", { lo = 0x8000 })
  lowest = math.min(lowest, w.raw)
end
check("never below the limit after WA's clamp", lowest == 0x8000, lowest)
check("rests at the limit", w.raw == 0x8000, w.raw)
frames(w, 2, "up", { lo = 0x8000 })
start = w.raw
frames(w, 5, "up", { lo = 0x8000 })
check("then up at full speed", w.raw - start == 5 * 4 * 0x200, (w.raw - start) / 0x200)

-- Never past straight up or down.
setup(400)
w = worm(0xF000)
frames(w, 40, "up")
check("stops straight up", w.raw == 0x10000, w.raw)
frames(w, 80, "down")
check("stops straight down", w.raw == 0, w.raw)

-- Turning round mid-press: the new direction is taken on.
setup(200)
w = worm(0x8000)
frames(w, 6, "up")
frames(w, 2, "down")
start = w.raw
frames(w, 5, "down")
check("reversal at full speed", start - w.raw == 10 * 0x200, (start - w.raw) / 0x200)

-- A coarse aim (the Blow Torch) is WA's own.
setup(400)
w = worm(0x8000)
frames(w, 64, "up", { step = 0x4000 })
check("coarse aim untouched", w.writes == 0 and w.raw == 0x10000, w.raw)

-- Only the turn's worm with its weapon out.
setup(200)
w = worm(0x4000)
w.aiming = false
frames(w, 20, "up")
check("not aiming: WA's speed", w.raw == 0x4000 + 20 * 0x200 and w.writes == 0, w.raw)

-- An older DLL without worm.aim_target: nothing, no error.
setup(200)
w = setmetatable({ id = 1, turn = true, aiming = true }, { __index = function(_, k)
  if k == "aim_target" then error("no field aim_target") end
end })
local ok = pcall(handler, w)
check("older DLL: off, no error", ok)

if failed > 0 then error(failed .. " FAILED") end
print("Fast aim: Shift scales WA's own aim steps from 1% to 400%, within its limits: PASS")
