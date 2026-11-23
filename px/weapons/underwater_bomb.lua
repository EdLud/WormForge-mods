-- Underwater Bomb: a swimming worm moors a bomb in the water; anything that comes near sets it off.

local weapon = {}

local ID = "px.underwater_bomb"
local ART = "sprites/underwater_bomb/"
local BOMB, CHAIN = ART .. "wbomb.png", ART .. "wbomb_ch.png"
local DEPTH = 40 -- how far below the water line the worm must be
local AHEAD = 65 -- pixels in front of the worm
local REACH = 36 -- anything this near sets it off
local BOB = 10 -- pixels either way
local BLAST = { damage = 100, id = 85 }
local SINK_SOUND = 58
local DRAW_DY, DRAW_SCALE = 72, 1.25 -- the bomb hangs from its chain below where it floats
local NEAR = 75 -- within this of the turn's worm (past touching) it reddens

local bombs = {}

local function swimming(worm)
  return worm.y >= wa.world.water() + DEPTH
end

-- Enter, as a swimmer's instant-use utility: "eat" leaves the unit where
-- the worm isn't deep enough.
local function moor(worm)
  if not swimming(worm) then
    pcall(worm.equip, worm, "stock.bungee")
    require("lib/weapon_hint").notice(worm, "This weapon must be used while swimming!")
    return "eat"
  end
  local b = {
    x0 = worm.x + worm.facing * AHEAD, y0 = worm.y,
    period_x = wa.random(65, 100), period_y = wa.random(65, 100),
    dir_x = wa.random(0, 1) == 0 and -1 or 1, dir_y = wa.random(0, 1) == 0 and -1 or 1,
    mirror = wa.random(0, 20) % 2 == 0,
  }
  local gone = false
  local function step(a)
    if gone then return end
    local frame = wa.world.frame()
    a:warp({ x = b.x0 + wa.math.cos(frame / b.period_x) * b.dir_x * BOB,
      y = b.y0 + wa.math.sin(frame / b.period_y) * b.dir_y * BOB, vx = 0, vy = 0 })
    local x, y = a.x, a.y
    local near = { near = { x, y, REACH } }
    local hit = wa.worms.all(near)[1] or wa.mines.all(near)[1] or wa.missiles.all(near)[1]
      or wa.crates.all(near)[1] or wa.oil.all(near)[1]
    if not hit then
      for _, other in ipairs(wa.actors.all(near)) do
        if not bombs[other.id] then hit = other; break end
      end
    end
    if hit then
      gone = true
      bombs[a.id] = nil
      a:explode(BLAST)
      a:remove()
    end
  end
  local a = wa.actors.spawn({ sprite = false, owner = worm, x = b.x0, y = b.y0, persist = true, light = false, on = step })
  bombs[a.id] = { actor = a, mirror = b.mirror }
  wa.sound.play(a, SINK_SOUND)
end

weapon.defaults = { instant_use = "manual" }
weapon.requires = { "lib/turn_controls" }

-- A utility, so the worm holds nothing.
weapon.definition = {
  copy_from = "stock.double_turn_time",
  name = "Underwater Bomb",
  panel_icon = ART .. "wbomb_ico.png",
  handling = { remember_selection = false, ends_turn = false, retreat = 3000 },
  utility = { effect = "scripted" },
  sprites = { BOMB, CHAIN },
  params = { gpu_prefix = ART },
}

function weapon.configure(ctx)
  require("lib/turn_controls").configure(ID, ctx.data)
end

local W, H = 48 * DRAW_SCALE / 2, 160 * DRAW_SCALE / 2

local function quad(sheet, x, y, color, mirror)
  local l, r = x - W, x + W
  if mirror then l, r = r, l end
  local top, bottom = y + DRAW_DY - H, y + DRAW_DY + H
  wa.draw.quad({ points = { { l, top }, { r, top }, { r, bottom }, { l, bottom } },
    sprite = sheet, color = color, depth = wa.depth.OBJECTS })
end

local function argb(a, r, g, b)
  local c = function(v) return math.max(0, math.min(255, math.floor(v * 2))) end
  return a * 0x1000000 + c(r) * 0x10000 + c(g) * 0x100 + c(b)
end

function weapon.setup()
  bombs = {}
  require("lib/turn_controls").register(ID, { fire = moor })
  wa.on.draw(function()
    local turn
    for _, w in ipairs(wa.worms.all()) do if w.turn then turn = w; break end end
    for _, b in pairs(bombs) do
      local a = b.actor
      if a.alive then
        local red, blue = 50, 125
        if turn then
          local d = math.sqrt((a.x - turn.x) ^ 2 + (a.y - turn.y) ^ 2) - 14
          if d <= NEAR then red, blue = 50 + (NEAR - d) * 1.5, 125 - (NEAR - d) end
        end
        quad(BOMB, a.x, a.y, argb(250, red, 50, blue), b.mirror)
        quad(CHAIN, a.x, a.y, argb(250, 50, 50, 125), false)
      end
    end
    -- Where the bomb will go, while the turn's swimmer holds it.
    if turn and turn.weapon == ID and swimming(turn) then
      local pulse = 15 + math.abs(wa.world.frame() % 50 - 25)
      quad(BOMB, turn.x + turn.facing * AHEAD, turn.y, argb(pulse, 125, 125, 125), false)
    end
  end)
end

return weapon
