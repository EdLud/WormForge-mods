-- PX Antifire Suit: one worm, until its team's next real turn (Tab is not a
-- turn), or as the profile sets it: for its team's next N turns, or for N
-- seconds and no longer than the turn, as WA's utilities.
local ART = "sprites/antifire_suit/"
local SOUND = "sounds/antifire_suit/putting_on_suit.wav"
local RADIUS, POWER = 28, 28
local IDLE_ALPHA, HIT_ALPHA = 38, 120
local M = {}

function M.install(ctx)
  local function option(key, default)
    if ctx and ctx.option then return ctx.option(key) end
    return default
  end
  -- 0: turn-based, else this many seconds (50 frames each).
  local seconds = option("duration", 0)
  local turns = option("turns", 1)
  local suits, smoke = {}, {}
  local function alive(w)
    return w.id ~= 0 and w.hp > 0 and w.state ~= "dying"
      and w.state ~= "drowning" and w.state ~= "dead"
  end
  local function alpha(s, now)
    return math.max(IDLE_ALPHA, s.alpha - 2 * math.max(0, now - s.refreshed - 51))
  end
  local function flash(s)
    local now = wa.world.frame()
    s.alpha, s.refreshed = HIT_ALPHA, now
  end
  wa.weapons.replace{
    copy_from = "stock.double_turn_time", name = "Antifire Suit",
    panel_icon = ART .. "icon.png",
    handling = {remember_selection = false, ends_turn = false, retreat = -1},
    utility = {effect = "scripted"},
    sprites = {ART .. "shield.png", ART .. "smoke.png"}, sounds = {SOUND}, params = {gpu_prefix = ART},
    on_fire = function(ev)
      local w = ev.worm
      if not alive(w) or suits[w.id] then return end
      local now = wa.world.frame()
      suits[w.id] = {team = w.team, alpha = IDLE_ALPHA, refreshed = now,
        turns = turns, ends = seconds > 0 and now + seconds * 50 or nil}
      wa.sound.play(w, SOUND)
      require("wf-lib/tooltip").notice(w, "Antifire Suit ON")
    end,
  }
  wa.on.hurt(function(hit)
    local w = hit.worm
    local s = suits[w.id]
    if hit.phase == "pre" and hit.kind == "fire" and s and alive(w) then
      flash(s)
      local now = wa.world.frame()
      if wa.world.turn_clock() > 0 then
        if now % 2 == 0 and s.sizzled ~= now then
          s.sizzled = now
          wa.sound.play(w, 55)
        end
        if now % 5 == 0 and s.smoked ~= now then
          s.smoked = now
          -- Presentation data only. No actors, collision bodies or WA RNG.
          for i = #smoke, 1, -1 do
            if now - smoke[i].born >= 60 then table.remove(smoke, i) end
          end
          if #smoke < 256 then
            smoke[#smoke + 1] = {id = w.id, x = w.x, y = w.y, born = now,
              vx = (now % 3 - 1) * 0.3}
          end
        end
      end
      -- Eating the native hit prevents its knockback and interruption too.
      return "eat"
    end
  end)
  wa.on.worm_message(function(w, msg)
    if msg == wa.msg.TURN_STARTED then
      if not w.turn then return end
      -- Turn-based: one of the team's turns has passed.
      for _, id in ipairs(wa.sorted(suits)) do
        local s = suits[id]
        if s.team == w.team and not s.ends then
          s.turns = s.turns - 1
          if s.turns <= 0 then suits[id] = nil end
        end
      end
      return
    end
    local s = suits[w.id]
    if not s then return end
    if not alive(w) or (s.ends and wa.world.frame() >= s.ends) then suits[w.id] = nil; return end
    wa.fire.repel{x = w.x, y = w.y, radius = RADIUS, power = POWER}
  end, {msgs = {wa.msg.FRAME_FINISH, wa.msg.TURN_STARTED}})
  wa.on.death(function(ev) suits[ev.victim.id] = nil end)
  -- Timed suits come off when the turn is cleaned up, as WA's utilities do.
  wa.on.turn_cleanup(function()
    for _, id in ipairs(wa.sorted(suits)) do
      if suits[id].ends then suits[id] = nil end
    end
  end)
  wa.on.draw(function()
    local now = wa.world.frame()
    local living = {}
    for _, w in ipairs(wa.worms.all()) do
      living[w.id] = w
      local s = suits[w.id]
      if s and alive(w) then
        local a = math.floor(alpha(s, now))
        if a > 0 then
          local r = 25 * 0.85
          wa.draw.quad{sprite = ART .. "shield.png", frame = 0,
            depth = wa.depth.WORMS - 1, visibility = w, blend = "add",
            color = (a << 24) | 0xFF0000,
            points = {{w.x-r,w.y-r},{w.x+r,w.y-r},{w.x+r,w.y+r},{w.x-r,w.y+r}}}
        end
      end
    end
    for i = #smoke, 1, -1 do
      local p = smoke[i]
      local age, w = now - p.born, living[p.id]
      if age >= 60 or not w or not alive(w) then table.remove(smoke, i)
      else
        local x, y = p.x + p.vx * age, p.y - 0.375 * age - 0.03 * age * age
        local opacity = math.floor(200 * (1 - age / 60))
        wa.draw.quad{sprite = ART .. "smoke.png", frame = math.min(27, math.floor(age * 28 / 60)),
          depth = wa.depth.WORMS - 2, visibility = w,
          color = (opacity << 24) | 0xFFFFFF,
          points = {{x-22,y-22},{x+22,y-22},{x+22,y+22},{x-22,y+22}}}
      end
    end
  end)
end

return M
