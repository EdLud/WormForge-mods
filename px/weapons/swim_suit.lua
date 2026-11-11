-- Swim Suit: worn, a worm swims instead of drowning, steered with the arrow keys.

local weapon = {}

weapon.record = {}

weapon.defaults = { auto_use = false, crate = { type = "utility" }, donor_card = true }

local automatic = false
local fast_walk_auto_use = false
local placed = {} -- every placed weapon's id, in slot order

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.laser_sight",
    name = "Swim Suit",
    panel_icon = "sprites/swim_suit/ico_swimsuit.png",
    sprites = { "sprites/swim_suit/swim.png", "sprites/swim_suit/float.png", "sprites/swim_suit/ring.png" },
    sounds = { "sounds/swim_suit/putting_on_ssuit.wav" },
    params = { gpu_prefix = "sprites/swim_suit/" },
  })
end

function weapon.setup()
  local shared = require("lib/shared")
  local own_time = require("wf-lib/own_time")
  local current_worm = shared.current_worm

  do

  local SWIM_CAP = 2.5 -- pixels a frame, times the swim speed
  local SWIM_PUSH = 0.1
  local SWIM_DRAG = 1.05
  local SWIM_STILL = 0.05
  local SWIM_KNOCK = 0.5 -- of WA's knock, a swimmer's push
  local SWIM_FLOAT_STEP = 0.0099
  local SWIM_DEPTH = 180 -- how far under the water the suit holds
  local SWIM_SUIT_MASK = 134342 -- 0x20CC6: the worm's 0x420CC6 without SWIM_WATER
  local SWIM_WATER = 0x400000
  local SWIM_MISSILE_MASK = 0x40007C -- a missile in the water that hits worms
  local SWIM_SPLASH = 57 -- WA's sound
  local SWIM_PLOP = 56
  local SWIM_BODY_DEPTH = wa.depth.FRONT
  local SWIM_RING_DEPTH = wa.depth.FRONT + 1
  local SWIM_RING_HALF = 25
  local SWIM_HALF_W, SWIM_HALF_H = 4, 6

  local DIVE_SPEED = 8
  local DIVE_FRAMES = 2000 -- the longest fall traced
  local FALLING = { [0x79] = true, [0x7A] = true, [0x7E] = true }

  local swim_speed = 2 -- fastswim: Fast Walk switches 2 and 6
  local swim_in_game = false -- SwimInGame: someone has worn the suit
  local turn_over = false -- between WA's turn end and the next turn's start
  local pending = nil
  local swim_fire = nil
  local function clickable(id)
    local ok, data = pcall(wa.weapons.data, id)
    local f = ok and type(data) == "table" and data.fires or nil
    return f ~= nil and (f.as == "strike" or f.as == "special" and (f.subtype == 10 or f.subtype == 17))
  end
  local function fireable()
    if not swim_fire then
      swim_fire = { list = { "stock.fast_walk" }, set = { ["stock.fast_walk"] = true } }
      for _, id in ipairs(placed) do
        if not swim_fire.set[id] and clickable(id) then
          swim_fire.list[#swim_fire.list + 1] = id
          swim_fire.set[id] = true
        end
      end
    end
    return swim_fire
  end
  local function swim_take(worm)
    worm:take{ turn = "run", fire = fireable().list, fire_as = "bungee" }
  end

  local swimmers = {}

  local function swimmer_of(worm)
    local s = swimmers[worm.id]
    if not s then
      s = { suit = false, plopready = false, plopped = false, floating = false,
        plophase = 0, flophase = 0, fmult = 5, keys = {} }
      swimmers[worm.id] = s
    end
    return s
  end

  local function swim_drop_art(worm, s)
    if s.body then s.body:despawn(); s.body = nil end
    worm.body_visible = true
  end

  local function suit_on(worm, s)
    wa.sound.play(worm, "sounds/swim_suit/putting_on_ssuit.wav")
    s.suit, s.plopready = true, true
    swim_in_game = true
    worm.collision_mask = SWIM_SUIT_MASK
  end

  local function suit_off(worm, s, sink, vx, vy)
    s.suit, s.plopready, s.plopped, s.floating = false, false, false, false
    swim_drop_art(worm, s)
    if sink then
      worm:release(vx, vy, { tumble = true })
    end
    worm.collision_mask = worm.collision_mask | SWIM_WATER
  end

  shared.swim_suit_off = function(worm)
    local s = swimmers[worm.id]
    if s and s.suit then suit_off(worm, s, false) end
  end

  local function swim_blocked(x, y)
    return wa.land.solid(x - SWIM_HALF_W, y) or wa.land.solid(x + SWIM_HALF_W, y)
      or wa.land.solid(x, y - SWIM_HALF_H) or wa.land.solid(x, y + SWIM_HALF_H)
  end

  local function swim_push(v, dir, cap)
    if dir > 0 then
      if v < cap then return v + SWIM_PUSH * swim_speed end
      return cap
    end
    if v > -cap then return v - SWIM_PUSH * swim_speed end
    return -cap
  end

  local KNOCKED = { [0x7F] = true, [0x80] = true, [0x81] = true }

  local function dive_step(worm, x, y, vx, vy)
    vx = vx + wa.world.wind() * (worm.wind or 0)
    vy = vy + wa.world.gravity() * (worm.gravity or 1)
    local nx, ny = x + vx, y + vy
    if wa.land.trace(x, y, nx, ny) or not worm:fits(nx, ny) then
      return vx, vy, x, y, true
    end
    return vx, vy, nx, ny, false
  end

  local function dives_into_water(worm, x, y, vx, vy, water)
    for _ = 1, DIVE_FRAMES do
      local blocked
      vx, vy, x, y, blocked = dive_step(worm, x, y, vx, vy)
      if blocked then return false end
      if y >= water then return true end
    end
    return false
  end

  local function swim_frame(worm)
    local s = swimmers[worm.id]
    if not s or not s.suit then
      return
    end
    local water = wa.world.water()
    local cap = SWIM_CAP * swim_speed
    if s.dive and not worm.taken then
      s.dive = nil
    end
    if not FALLING[worm.state_id] and not s.dive then
      s.dived = false
    end
    if s.plopready and not s.dive and not s.dived and worm.turn and FALLING[worm.state_id]
      and worm.y < water
      and worm.vy + 2 * wa.world.gravity() * (worm.gravity or 1) >= DIVE_SPEED then
      s.dived = true
      if dives_into_water(worm, worm.x, worm.y, worm.vx, worm.vy, water) then
        s.dive = { x = worm.x, y = worm.y, vx = worm.vx, vy = worm.vy }
        worm:take{ turn = "run" }
      end
    end
    local dive_into
    if s.dive then
      local d = s.dive
      for _ = 1, own_time.frames(worm) do
        local blocked
        d.vx, d.vy, d.x, d.y, blocked = dive_step(worm, d.x, d.y, d.vx, d.vy)
        if blocked then
          s.dive = nil
          worm.x, worm.y = d.x, d.y
          worm:release(d.vx, d.vy)
          return
        end
        if d.y >= water then break end
      end
      worm:carry(d.x, d.y)
      if d.y < water then
        return
      end
      s.dive, dive_into = nil, d
    end
    if worm.y >= water and s.plopready and KNOCKED[worm.state_id] then
      suit_off(worm, s, false)
      return
    end
    if dive_into or worm.y >= water and s.plopready and worm.state ~= "teleporting" then
      local d = dive_into or worm
      wa.sound.play(worm, SWIM_SPLASH)
      s.plopready, s.plopped = false, true
      s.x, s.y = d.x, d.y
      s.vx, s.vy = math.min(d.vx, cap), math.min(d.vy, cap)
      s.px, s.py, s.knocked = 0, 0, false
      if worm.state == "roping" or worm.state == "bungee" then
        worm:release(s.vx, s.vy)
      end
      swim_take(worm)
      s.plophase = 0
    end
    if s.plopped and not worm.taken and KNOCKED[worm.state_id] and not turn_over then
      swim_take(worm)
      s.px = s.px + worm.vx * SWIM_KNOCK
      s.py = s.py + worm.vy * SWIM_KNOCK
      s.knocked = true
    elseif s.knocked and worm.taken then
      s.knocked = false
      if KNOCKED[worm.state_id] then
        worm:release(0, 0)
        swim_take(worm)
      end
    end
    if s.plopped and not worm.taken and worm.state == "teleporting" then
      s.floating = false
      s.plopready, s.plopped = true, false
      s.px, s.py, s.knocked = 0, 0, false
      swim_drop_art(worm, s)
      return
    end
    if s.plopped and not worm.taken then
      suit_off(worm, s, true, worm.vx, worm.vy)
      return
    end
    if s.plopped then
      local out
      for _ = 1, own_time.frames(worm) do
        local vx, vy = math.min(s.vx, cap), math.min(s.vy, cap)
        local held = s.keys
        local still = math.abs(vx) <= SWIM_STILL * swim_speed and math.abs(vy) <= SWIM_STILL * swim_speed
        if still and not (held.left or held.up or held.down or held.right) then
          s.floating = true
          s.flophase = s.flophase + SWIM_FLOAT_STEP * s.fmult
          if s.flophase >= 0.99 and s.fmult == 5 then
            s.flophase, s.fmult = 0.99, -5
          elseif s.flophase <= 0 and s.fmult == -5 then
            s.flophase, s.fmult = 0, 5
          end
        elseif vx ~= 0 and vy ~= 0 then
          s.floating = false
          if math.abs(vx) >= math.abs(vy) then
            s.plophase = s.plophase + SWIM_FLOAT_STEP * vx * worm.facing
          else
            s.plophase = s.plophase - SWIM_FLOAT_STEP * vy
          end
        elseif vx ~= 0 then
          s.floating = false
          s.plophase = s.plophase + SWIM_FLOAT_STEP * vx
        elseif vy ~= 0 then
          s.floating = false
          s.plophase = s.plophase - SWIM_FLOAT_STEP * vy
        end
        if s.plophase >= 1 or s.plophase <= -1 then
          s.plophase = 0
        end
        local k = worm.keys
        local up, down, left, right = k.up, k.down, k.left, k.right
        if up == down then vy = vy / SWIM_DRAG end
        if left == right then vx = vx / SWIM_DRAG end
        if up then vy = swim_push(vy, -1, cap) end
        if down then vy = swim_push(vy, 1, cap) end
        local shift = wa.world.keys().shift
        if left then
          if not shift then worm.facing = -1 end
          vx = swim_push(vx, -1, cap)
        end
        if right then
          if not shift then worm.facing = 1 end
          vx = swim_push(vx, 1, cap)
        end
        s.keys = { up = up, down = down, left = left, right = right }
        local px, py = s.px, s.py
        local stuck = swim_blocked(s.x, s.y)
        local nx = s.x + vx + px
        if not stuck and swim_blocked(nx, s.y) then vx, px = 0, 0 else s.x = nx end
        local ny = s.y + vy + py
        if not stuck and swim_blocked(s.x, ny) then vy, py = 0, 0 else s.y = ny end
        s.vx, s.vy = vx, vy
        s.px, s.py = px / SWIM_DRAG, py / SWIM_DRAG
        if math.abs(s.px) < SWIM_STILL then s.px = 0 end
        if math.abs(s.py) < SWIM_STILL then s.py = 0 end
        if s.y < water then
          s.floating = false
          s.plopready, s.plopped = true, false
          s.px, s.py, s.knocked = 0, 0, false
          worm.x, worm.y = s.x, s.y
          worm:release(vx + px, vy + py)
          wa.sound.play(worm, SWIM_PLOP)
          out = true
          break
        end
      end
      if not out then
        worm:carry(s.x, s.y)
        local y, w = s.y, water
        local deep
        if not wa.world.cavern() then
          deep = y > w + SWIM_DEPTH
        elseif w > 610 then
          deep = y > w + SWIM_DEPTH
        else
          deep = y > 768
        end
        if deep then
          suit_off(worm, s, true, s.vx, s.vy)
          return
        end
      end
    end
    if not current_worm() and worm.y < water then
      suit_off(worm, s, false)
      return
    end
    local function art(sheet)
      local a = wa.actors.spawn({
        sprite = sheet, x = worm.x, y = worm.y, gravity = false,
        collide = false, owner = worm, visibility = worm, on = function() end,
      })
      a:gfx({ follow = worm })
      return a
    end
    if s.plopped then
      local sheet = s.floating and "sprites/swim_suit/float.png" or "sprites/swim_suit/swim.png"
      if s.body and s.body_sheet ~= sheet then
        s.body:despawn()
        s.body = nil
      end
      s.body = s.body or art(sheet)
      s.body_sheet = sheet
      local phase = s.floating and s.flophase or s.plophase
      s.body.x, s.body.y, s.body.vx, s.body.vy = s.x, s.y, 0, 0
      s.body.facing = -worm.facing
      s.body:frame(math.floor((phase % 1) * 20) % 20)
      s.body:gfx({ depth = SWIM_BODY_DEPTH })
      worm.body_visible = false
    elseif s.body then
      s.body:despawn()
      s.body = nil
      worm.body_visible = true
    end
  end

  if wa.on.draw then
    wa.on.draw(function()
      for _, worm in ipairs(wa.worms.all()) do
        local s = swimmers[worm.id]
        if s and s.suit then
          local x, y, h = worm.x, worm.y, SWIM_RING_HALF
          wa.draw.quad({
            points = {
              { x - h, y - h }, { x + h, y - h }, { x + h, y + h }, { x - h, y + h },
            },
            sprite = "sprites/swim_suit/ring.png",
            visibility = worm,
            depth = SWIM_RING_DEPTH,
          })
        end
      end
    end)
  end

  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FRAME_FINISH then
      if pending == worm.id and worm.turn then
        pending = nil
        local s = swimmer_of(worm)
        if not s.suit and worm:ammo("px.swim_suit") ~= 0 then
          suit_on(worm, s)
          worm:ammo("px.swim_suit", -1)
        end
      end
      swim_frame(worm)
    elseif msg == wa.msg.JUMP then
      local s = swimmers[worm.id]
      if s and s.plopped then
        return "eat"
      end
    elseif msg == wa.msg.FIRE_WEAPON then
      local s = swimmers[worm.id]
      if s and s.plopped and not fireable().set[worm.weapon] then
        return "eat" -- nothing else while it swims
      end
      if worm.weapon == "stock.fast_walk" then
        swim_speed = swim_speed ~= 6 and 6 or 2
      elseif worm.weapon == "px.swim_suit" then
        local s = swimmer_of(worm)
        if not s.suit then
          suit_on(worm, s)
        elseif worm.y < wa.world.water() then
          suit_off(worm, s, false)
        end
        worm:ammo("px.swim_suit", -1)
        return "eat"
      end
    end
  end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.JUMP, wa.msg.FIRE_WEAPON } })

  wa.on.turn_start(function(ev)
    turn_over = false
    swim_speed = fast_walk_auto_use and 6 or 2
    if automatic and ev.worm then pending = ev.worm.id end
  end)

  wa.on.turn_end(function()
    turn_over = true
  end)

  wa.on.missile_frame(function(m)
    if swim_in_game and m.phase == "pre" and m.collision_mask == SWIM_WATER then
      m.collision_mask = SWIM_MISSILE_MASK
    end
  end)

  if wa.on.contact then
    wa.on.contact(function(worm, other)
      local s = swimmers[worm.id]
      if s and s.plopped and other.kind == "missile" then
        wa.actors.spawn({
          sprite = false, x = other.x, y = other.y, gravity = false, collide = false,
          owner = worm, explode = { damage = 100, id = 50, now = true },
        })
        other.y = wa.world.water() + 4096
      end
    end)
  end
  end
end

function weapon.configure(ctx)
  automatic = ctx.data.auto_use == true
  placed = {}
  for _, p in ipairs(ctx.placed or {}) do placed[#placed + 1] = p.id end
  local fast_walk = ctx.weapons["stock.fast_walk"]
  fast_walk_auto_use = fast_walk ~= nil and fast_walk.data.auto_use == true
end

return weapon
