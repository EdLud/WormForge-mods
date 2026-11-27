-- Weather: what is falling now, picked by the shares of clear skies, rain and snow at each turn cycle.
local L = require("wf-lib/lightning")

local W = {}

W.RAIN_SOUND, W.SNOW_SOUND = "sounds/rain.wav", "sounds/blizzard.wav"
local SPRITES = { "sprites/rain.png", "sprites/splash.png", "sprites/ring.png", "sprites/oval.png", "sprites/flat.png",
  "sprites/flake.png", "sprites/settle.png", "sprites/glow.png" }
local KINDS = { "rain", "snow" }
local FADE = 150 -- frames a kind takes to fade in or out on screen
local SECOND = 50 -- frames

-- The settings of each kind in play.
W.kinds = {}
-- Whether each kind falls now, 0 or 1: set before the match and in simulation callbacks only.
W.target = { rain = 0, snow = 0 }
-- "clear", "rain" or "snow"; nil before the first turn while more than one has a share.
W.kind = nil
W.cycles = 0
-- Simulation handlers: every frame from the first turn, at the start of each turn cycle, and of each turn.
W.ticks, W.on_cycle, W.on_turn = {}, {}, {}

local cycle_cfg
local set_up, begun, ticking = false, false, false

-- The weather of a turn cycle, by the shares: drawn only when more than one has a share.
function W.next_kind(cfg)
  local total, choices = 0, {}
  for _, kind in ipairs({ "clear", "rain", "snow" }) do
    if cfg[kind] > 0 then
      total = total + cfg[kind]
      choices[#choices + 1] = { kind, total }
    end
  end
  if #choices == 0 then return "clear" end
  if #choices == 1 then return choices[1][1] end
  local r = wa.random(1, total)
  for _, c in ipairs(choices) do
    if r <= c[2] then return c[1] end
  end
end

function W.set_kind(kind)
  W.kind = kind
  for _, k in ipairs(KINDS) do W.target[k] = (k == kind and W.kinds[k]) and 1 or 0 end
end

-- The first turn: the first weather, then the clock of the simulation.
local function begin()
  if cycle_cfg and not W.kind then W.set_kind(W.next_kind(cycle_cfg)) end
  ticking = #W.ticks > 0
end

-- A turn cycle starts when a team that already played since the last one plays again.
local seen, last_team, in_turn = {}, nil, false
local function turn_start(ev)
  if not begun then
    begun = true
    begin()
  end
  local team = ev and ev.worm and ev.worm.team
  -- A worm switch within the turn (Tab, Select Worm) starts it again for the same team.
  if in_turn and team == last_team then return end
  in_turn, last_team = true, team
  if team ~= nil then
    if seen[team] then
      seen = {}
      W.cycles = W.cycles + 1
      if cycle_cfg then W.set_kind(W.next_kind(cycle_cfg)) end
      for _, f in ipairs(W.on_cycle) do f(W.cycles) end
    end
    seen[team] = true
  end
  for _, f in ipairs(W.on_turn) do f() end
end

local function turn_end() in_turn = false end

local draws, sounds = nil, {}
local st, last = { rain = nil, snow = nil }, nil

local function approach(v, target, step)
  if v < target then return math.min(target, v + step) end
  return math.max(target, v - step)
end

-- A number 0..1 for whole number k, the same on every machine and every playback.
local function noise(k)
  local x = (k * 0x9E3779B1 + 0x7F4A7C15) & 0xFFFFFFFF
  x = ((x ~ (x >> 15)) * 0x2C1B3C6D) & 0xFFFFFFFF
  x = ((x ~ (x >> 12)) * 0x297A2D39) & 0xFFFFFFFF
  return (x ~ (x >> 15)) / 0xFFFFFFFF
end

-- How heavy the rain is at `now`: a level between its lightest and heaviest, picked every `every` seconds, ramping
-- from each level to the next all the way between them.
function W.rain_amount(cfg, now)
  local span = cfg.amount - cfg.amount_low
  if span <= 0 then return cfg.amount end
  local every = cfg.every * SECOND
  local k = math.floor(now / every)
  local into = (now - k * every) / every
  local level = noise(k) + (noise(k + 1) - noise(k)) * into
  return cfg.amount_low + span * level
end

-- Each rendered frame: the view, the kinds eased in and out, then every part drawn.
local function draw()
  local v = wa.world.view()
  if v.w <= 0 or v.h <= 0 then return end
  if not draws then
    draws = {}
    for _, name in ipairs({ "lib/sky", "lib/rain", "lib/surface", "lib/snow", "lib/glow" }) do
      draws[#draws + 1] = require(name).install(W)
    end
  end
  local z = v.zoom > 0 and v.zoom or 1
  local hw, hh = v.w / z / 2, v.h / z / 2
  st.cx, st.cy, st.zoom = v.cx, v.cy, z
  st.left, st.right, st.top, st.bottom = v.cx - hw, v.cx + hw, v.cy - hh, v.cy + hh
  if wa.world.cavern() then
    -- A cavern smaller than the screen sits in black bars: nothing past it.
    local size = wa.world.size()
    st.left, st.right = math.max(st.left, 0), math.min(st.right, size.w)
    st.top, st.bottom = math.max(st.top, 0), math.min(st.bottom, size.h)
  end
  st.w, st.h = st.right - st.left, st.bottom - st.top
  st.now = wa.world.frame() + wa.draw.fraction()
  st.wind = wa.world.wind()
  st.water = wa.world.water()
  local rain = W.kinds.rain
  st.rain_amount = rain and W.rain_amount(rain, st.now) or nil
  local step = last and st.now - last or 0
  if step < 0 or step > 50 then step = 0 end
  last = st.now
  for _, k in ipairs(KINDS) do
    st[k] = st[k] and approach(st[k], W.target[k], step / FADE) or W.target[k]
    local cfg = W.kinds[k]
    if cfg and wa.sound.ambient and cfg.volume > 0 and cfg.amount > 0 then
      -- The rain is louder as it gets heavier.
      local volume = k == "rain" and cfg.volume * (0.2 + 0.8 * st.rain_amount)
        or math.min(1, cfg.volume * (0.4 + 0.6 * cfg.amount))
      volume = volume * st[k]
      local s = sounds[k]
      if not s then
        sounds[k] = { handle = wa.sound.ambient({ path = k == "rain" and W.RAIN_SOUND or W.SNOW_SOUND,
          volume = volume, fade_ms = 3000 }), volume = volume }
      elseif math.abs(volume - s.volume) > 0.02 or (volume == 0 and s.volume > 0) then
        s.handle:set({ volume = volume, fade_ms = 500 })
        s.volume = volume
      end
    end
  end
  for _, d in ipairs(draws) do d(st) end
end

local function setup()
  if set_up then return end
  set_up = true
  local sprites = {}
  for _, path in ipairs(SPRITES) do sprites[#sprites + 1] = path end
  for _, path in ipairs(L.SPRITES) do sprites[#sprites + 1] = path end
  local sounds_list = { W.RAIN_SOUND, W.SNOW_SOUND }
  for _, path in ipairs(L.SOUNDS) do sounds_list[#sounds_list + 1] = path end
  wa.assets.load({ sprites = sprites, sounds = sounds_list })
  -- Keys taken now, while the add-on installs: in a draw they would name whichever mod drew last.
  W.keys = {}
  for _, path in ipairs(SPRITES) do W.keys[path] = wa.sprites.key(path) end
  wa.on.turn_start(turn_start)
  if wa.on.turn_end then wa.on.turn_end(turn_end) end
  -- The weather's clock, from the first turn on.
  wa.on.frame(function()
    if not ticking then return end
    local frame = wa.world.frame()
    for _, tick in ipairs(W.ticks) do tick(frame) end
  end)
  if wa.on.draw and wa.draw.brush and wa.draw.ribbon then
    L.setup()
    wa.on.draw(draw)
  end
end

-- The settings of a kind with a share: `amount` 0..1 is how heavy it falls (at 0 its clouds and darkness still
-- show), the rest its own.
function W.add(kind, cfg)
  setup()
  W.kinds[kind] = cfg
  W.target[kind] = W.kind == kind and 1 or 0
end

-- The shares of the weathers, and the melt. A weather with all the share is there from the match's start.
function W.cycle(cfg)
  setup()
  cycle_cfg = cfg
  W.cycle_cfg = cfg
  for _, kind in ipairs({ "clear", "rain", "snow" }) do
    if cfg[kind] >= 100 then W.set_kind(kind) end
  end
end

return W
