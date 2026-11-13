-- Weather: what is falling now, shared by the Rain, Snow and Weather cycle add-ons.
local L = require("wf-lib/lightning")

local W = {}

W.RAIN_SOUND, W.SNOW_SOUND = "sounds/rain.wav", "sounds/blizzard.wav"
local SPRITES = { "sprites/rain.png", "sprites/splash.png", "sprites/ring.png", "sprites/oval.png", "sprites/flat.png",
  "sprites/flake.png", "sprites/settle.png" }
local KINDS = { "rain", "snow" }
local FADE = 150 -- frames a kind takes to fade in or out on screen

-- The settings of each selected kind, from its add-on.
W.kinds = {}
-- Whether each kind falls now, 0 or 1: set before the match and in simulation callbacks only.
W.target = { rain = 0, snow = 0 }
-- With the cycle: "rain", "snow" or "clear".
W.kind = nil
W.cycles = 0
-- Simulation handlers: every frame from the first turn, and at the start of each turn cycle.
W.ticks, W.on_cycle = {}, {}

local cycle_cfg
local set_up, begun = false, false

-- A kind is in play when its add-on is selected and falls at all.
local function has(kind)
  local cfg = W.kinds[kind]
  return cfg ~= nil and cfg.amount > 0
end

-- The next weather of the cycle: one of the others, by their weights.
function W.next_kind(cfg, current)
  local total, choices = 0, {}
  for _, kind in ipairs({ "rain", "snow", "clear" }) do
    local weight = cfg[kind .. "_weight"]
    if kind ~= current and weight > 0 and (kind == "clear" or has(kind)) then
      total = total + weight
      choices[#choices + 1] = { kind, total }
    end
  end
  if total == 0 then return current end
  local r = wa.random(1, total)
  for _, c in ipairs(choices) do
    if r <= c[2] then return c[1] end
  end
end

function W.set_kind(kind)
  W.kind = kind
  for _, k in ipairs(KINDS) do W.target[k] = (k == kind and has(k)) and 1 or 0 end
end

-- Once every add-on has installed: the cycle brings rain and snow with their defaults when their add-ons
-- aren't selected, so it works alone.
local finished = false
local function finish()
  if finished then return end
  finished = true
  if not cycle_cfg then return end
  local settings = require("lib/settings")
  for _, k in ipairs(KINDS) do
    if not W.kinds[k] then
      W.kinds[k] = settings[k](settings.defaults(k))
      require(k == "rain" and "lib/sim" or "lib/settle").install(W)
    end
  end
  W.set_kind(W.kind)
end

-- The first turn: the first weather of the cycle, then the clock of the simulation.
local function begin()
  finish()
  if cycle_cfg then
    local start = cycle_cfg.start
    if start == "random" or (start ~= "clear" and not has(start)) then start = W.next_kind(cycle_cfg, nil) end
    W.set_kind(start or "clear")
  end
  if #W.ticks > 0 then
    local size = wa.world.size()
    wa.actors.spawn({
      sprite = "sprites/flat.png", visible = false, gravity = false, collide = false,
      owner = "none", x = size.w // 2, y = 0,
      on = function()
        local frame = wa.world.frame()
        for _, tick in ipairs(W.ticks) do tick(frame) end
      end,
    })
  end
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
  if team == nil then return end
  if seen[team] then
    seen = {}
    W.cycles = W.cycles + 1
    if cycle_cfg and wa.random(1, 100) <= cycle_cfg.change_chance then
      W.set_kind(W.next_kind(cycle_cfg, W.kind))
    end
    for _, f in ipairs(W.on_cycle) do f(W.cycles) end
  end
  seen[team] = true
end

local function turn_end() in_turn = false end

local draws, sounds = nil, {}
local st, last = { rain = nil, snow = nil }, nil

local function approach(v, target, step)
  if v < target then return math.min(target, v + step) end
  return math.max(target, v - step)
end

-- Each rendered frame: the view, the kinds eased in and out, then every part drawn.
local function draw()
  local v = wa.world.view()
  if v.w <= 0 or v.h <= 0 then return end
  if not draws then
    finish()
    draws = {}
    for _, name in ipairs({ "lib/sky", "lib/rain", "lib/surface", "lib/snow" }) do
      draws[#draws + 1] = require(name).install(W)
    end
  end
  local z = v.zoom > 0 and v.zoom or 1
  local hw, hh = v.w / z / 2, v.h / z / 2
  st.cx, st.cy, st.zoom = v.cx, v.cy, z
  st.left, st.right, st.top, st.bottom = v.cx - hw, v.cx + hw, v.cy - hh, v.cy + hh
  st.w, st.h = 2 * hw, 2 * hh
  st.now = wa.world.frame() + wa.draw.fraction()
  st.wind = wa.world.wind()
  st.water = wa.world.water()
  local step = last and st.now - last or 0
  if step < 0 or step > 50 then step = 0 end
  last = st.now
  for _, k in ipairs(KINDS) do
    st[k] = st[k] and approach(st[k], W.target[k], step / FADE) or W.target[k]
    local cfg = W.kinds[k]
    if cfg and wa.sound.ambient and cfg.volume > 0 and cfg.amount > 0 then
      local volume = math.min(1, cfg.volume * (0.4 + 0.6 * cfg.amount)) * st[k]
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
  if wa.on.draw and wa.draw.quads and wa.draw.ribbon then
    L.setup()
    wa.on.draw(draw)
  end
end

-- The settings of an add-on: `amount` 0..1 is how heavy it falls, the rest its own.
function W.add(kind, cfg)
  setup()
  W.kinds[kind] = cfg
  if cycle_cfg then
    W.target[kind] = (W.kind == kind and has(kind)) and 1 or 0
  else
    -- Selected, it stays all match: at 0 % its clouds and darkness still show.
    W.target[kind] = 1
  end
end

function W.cycle(cfg)
  setup()
  cycle_cfg = cfg
  W.cycle_cfg = cfg
  W.set_kind(cfg.start ~= "random" and cfg.start or nil)
end

return W
