-- Dynamite slot, mine placement. Space plants a persist LuaActor.
-- LOS with wa.land.trace, hitscan with worm:hurt. No stock blast.
return {
  install = function()
    local SENSOR_PX = 360
    local AMMO = 20
    local DAMAGE = 2
    local SHOT_FRAMES = 6
    local ARM_FRAMES = 30
    local BEEP_FRAMES = 60
    local ROT_IDLE = 3
    local ROT_ACTIVE = 8
    local AIM_TOLERANCE = 1.5
    local HIT_PX = 10
    local KNOCK = 1.75
    local STEPS = 120
    local SINK_PX = 8
    local MUZZLE_UP = 25
    local MUZZLE_OUT = 11
    local SPARK_LIFE = 10

    local SPREAD = { 0.0, 1.5, -1.0, 2.0, -2.0, 1.0, -1.5, 0.5 }

    local state = {}
    local sparks = {}

    local function turret_sheet(team, pose)
      return "sprites/turret_t" .. team .. "_p" .. pose .. ".gif"
    end

    local IMPACT = "sprites/uzihit.png"

    local SPRITES = { IMPACT }
    for t = 1, 6 do
      for pose = 0, 2 do
        SPRITES[#SPRITES + 1] = turret_sheet(t, pose)
      end
    end

    local function step_index(angle, steps)
      return math.floor((angle % 360) / (360 / steps) + 0.5) % steps
    end

    -- 0 = down, 90 = right: source art faces right, screen y grows down.
    local function angle_to(ax, ay, tx, ty)
      local dx = (tx - ax) // 1
      local dy = (ty - ay) // 1
      local deg = math.deg(wa.math.atan(dx, dy))
      if deg < 0 then
        deg = deg + 360
      end
      return deg
    end

    local function turn_toward(cur, want, speed)
      local d = (want - cur + 540) % 360 - 180
      if d > speed then
        d = speed
      elseif d < -speed then
        d = -speed
      end
      return (cur + d) % 360
    end

    local function angle_gap(a, b)
      local d = (a - b + 540) % 360 - 180
      return d < 0 and -d or d
    end

    local function enemy(s, w)
      if not w or w.hp <= 0 or w.visible == false then
        return false
      end
      return w.alliance ~= s.alliance
    end

    -- WA walks by stepping position with vx/vy still 0, so motion is last-tick pos.
    local function note_motion(s, w)
      local p = s.seen[w.id]
      if p then
        p.moving = (p.x ~= w.x or p.y ~= w.y or w.vx ~= 0 or w.vy ~= 0)
        p.x, p.y = w.x, w.y
      else
        s.seen[w.id] = { x = w.x, y = w.y, moving = (w.vx ~= 0 or w.vy ~= 0) }
      end
    end

    local function moving(s, w)
      local p = s.seen[w.id]
      return p ~= nil and p.moving
    end

    local function sees(a, s, w)
      if not enemy(s, w) or not moving(s, w) then
        return false
      end
      local ex, ey = a.x, a.y - MUZZLE_UP
      local dx = (w.x - ex) // 1
      local dy = (w.y - ey) // 1
      if dx * dx + dy * dy > SENSOR_PX * SENSOR_PX then
        return false
      end
      return not wa.land.trace(ex, ey, w.x, w.y)
    end

    local function acquire(a, s)
      local ex, ey = a.x, a.y - MUZZLE_UP
      local best, best_d
      for _, w in ipairs(wa.worms.all()) do
        if sees(a, s, w) then
          local dx = (w.x - ex) // 1
          local dy = (w.y - ey) // 1
          local d = dx * dx + dy * dy
          if not best_d or d < best_d or (d == best_d and w.id < best.id) then
            best, best_d = w, d
          end
        end
      end
      return best
    end

    local function held(a, s)
      if not s.tid then
        return nil
      end
      for _, w in ipairs(wa.worms.all()) do
        if w.id == s.tid then
          return sees(a, s, w) and w or nil
        end
      end
      return nil
    end

    local function spark_brain(a)
      local n = sparks[a.id] or 0
      a:frame(n)
      n = n + 1
      sparks[a.id] = n
      if n >= SPARK_LIFE then
        sparks[a.id] = nil
        a:despawn()
      end
    end

    local function spark_at(x, y)
      wa.actors.spawn({
        sprite = IMPACT,
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        gravity = false,
        collide = false,
        drown = false,
        loop = false,
        origin = "center",
        on = spark_brain,
      })
    end

    local function start_firing(a, s)
      if s.firing then return end
      s.firing = true
      s.anim = 0
      s.fire_sound = 35
      a:sound("sounds/sentryfireloop.wav")
    end

    local function stop_firing(a, s)
      if not s.firing then return end
      s.firing = false
      s.anim = 0
      a:sound("sounds/sentryfireend.wav")
    end

    local function fire(a, s)
      s.shots = s.shots + 1
      local dev = 0
      if s.shots % 5 ~= 0 then
        dev = SPREAD[(s.shots % #SPREAD) + 1]
      end

      local rad = math.rad(s.angle + dev)
      local dx, dy = wa.math.sin(rad), wa.math.cos(rad)
      local mx = a.x + (dx * MUZZLE_OUT)
      local my = a.y - MUZZLE_UP + (dy * MUZZLE_OUT)
      local reach = SENSOR_PX
      local ex = mx + (dx * reach)
      local ey = my + (dy * reach)

      local hit = wa.land.trace(mx, my, ex, ey)
      local hx, hy = ex, ey
      if hit then
        hx, hy = hit.x, hit.y
      end
      local rx, ry = (hx - mx) // 1, (hy - my) // 1
      local hit_px = rx * rx + ry * ry
      local victim
      for _, w in ipairs(wa.worms.all()) do
        if enemy(s, w) then
          local wx = (w.x - mx) // 1
          local wy = (w.y - my) // 1
          local along = wx * dx + wy * dy
          if along > 0 and along * along < hit_px then
            local off = wx * dy - wy * dx
            if off * off <= HIT_PX * HIT_PX then
              hx = mx + (dx * along)
              hy = my + (dy * along)
              hit_px = along * along
              victim = w
            end
          end
        end
      end

      if victim then
        victim:hurt(DAMAGE)
        victim.vx = victim.vx + (dx * KNOCK)
        victim.vy = victim.vy + (dy * KNOCK)
      end
      spark_at(hx, hy)

      s.ammo = s.ammo - 1
    end

    local function think(a, s)
      if s.px then
        a.x, a.y = s.px, s.py
      end
      a.vx, a.vy = 0, 0

      for _, w in ipairs(wa.worms.all()) do
        note_motion(s, w)
      end

      local can_shoot = s.arm <= 0 and s.ammo > 0
      local target
      if can_shoot then
        target = held(a, s)
        if not target then
          target = acquire(a, s)
          s.tid = target and target.id or nil
        end
      end

      local want
      if target then
        if not s.had_target then
          if s.beep <= 0 then
            a:sound("sounds/sentrybeeps2.wav")
            s.beep = BEEP_FRAMES
          end
        end
        s.had_target = true
        want = angle_to(a.x, a.y - MUZZLE_UP, target.x, target.y)
        s.angle = turn_toward(s.angle, want, ROT_ACTIVE)
      else
        s.had_target = false
        s.tid = nil
        s.angle = (s.angle + ROT_IDLE) % 360
      end

      if s.beep > 0 then s.beep = s.beep - 1 end
      if s.arm > 0 then s.arm = s.arm - 1 end
      if s.cooldown > 0 then s.cooldown = s.cooldown - 1 end
      if s.fire_sound > 0 then s.fire_sound = s.fire_sound - 1 end

      local aligned = target and angle_gap(s.angle, want) <= AIM_TOLERANCE
      if target and aligned then
        start_firing(a, s)
        if s.fire_sound <= 0 then
          s.fire_sound = 35
          a:sound("sounds/sentryfireloop.wav")
        end
        if s.cooldown <= 0 then
          fire(a, s)
          s.cooldown = SHOT_FRAMES
        end
      else
        stop_firing(a, s)
      end
    end

    local function sync(a, s)
      local pose = s.firing and (1 + ((s.anim // 3) % 2)) or 0
      local step = step_index(s.angle, STEPS)
      if pose ~= s.pose then
        a:look(turret_sheet(s.team, pose))
        s.pose = pose
        s.at = nil
      end
      if step ~= s.at then
        a:frame(step)
        s.at = step
      end
    end

    local function brain(a, ev)
      local s = state[a.id]
      if not s then
        return
      end
      ev = ev or {}
      if (ev.damage or 0) > 0 then
        s.health = s.health - ev.damage
        if s.health <= 0 then
          state[a.id] = nil
          a:despawn()
          return
        end
      end
      s.frames = s.frames + 1
      if s.firing then s.anim = s.anim + 1 end

      if not s.planted then
        a:gravity()
        local hit = a:move({ terrain = true, worms = false })

        if hit.land then
          a.vx, a.vy = 0, 0
          s.planted = true
          s.px, s.py = a.x, a.y + SINK_PX
          s.arm = ARM_FRAMES
          a:sound("sounds/sentryplace.wav")
          sync(a, s)
          return
        end

        a:advance()

        if a:in_water() then
          state[a.id] = nil
          a:despawn()
          return
        end
      else
        think(a, s)
      end

      sync(a, s)
    end

    wa.weapons.replace({
      copy_from = "stock.mine",
      name = "Sentry Gun",
      is_weapon = true,
      worm_sprites = {
        weaponlnk = "sprites/equip", weaponlnku = "sprites/equipu", weaponlnkd = "sprites/equipd",
        wthrow = "sprites/unequip", wthrowu = "sprites/unequipu", wthrowd = "sprites/unequipd",
      },
      params = {
        sprite_columns = 1,
      },
      sprites = SPRITES,
      sounds = {
        "sounds/sentryplace.wav", "sounds/sentrybeeps2.wav",
        "sounds/sentryfireloop.wav", "sounds/sentryfireend.wav",
      },
      on_fire = function(fire_ev)
        local worm = fire_ev.worm
        local team = (worm and worm.team) or 1
        if team < 1 or team > 6 then
          team = 1
        end
        local facing = worm.facing
        local idle = facing < 0 and 270 or 90

        local body = wa.actors.spawn({
          sprite = turret_sheet(team, 0),
          x = worm.x,
          y = worm.y,
          vx = (worm.vx / 2) + facing * 0.3000030517578125,
          vy = (worm.vy / 2) - 0.149993896484375,
          loop = false,
          origin = "bottom",
          owner = worm,
          kind = "sentry",
          persist = true,
          on = brain,
        })

        state[body.id] = {
          team = team,
          alliance = worm.alliance,
          owner_id = worm.id,
          planted = false,
          ammo = AMMO,
          health = 50,
          angle = idle,
          idle = idle,
          frames = 0,
          shots = 0,
          firing = false,
          anim = 0,
          fire_sound = 0,
          beep = 0,
          arm = 0,
          cooldown = 0,
          had_target = false,
          seen = {},
        }
        sync(body, state[body.id])
      end,
    })

    wa.on.worm_message(function(worm, msg)
      if msg ~= wa.msg.START_TURN then
        return
      end
      for _, s in pairs(state) do
        if s.owner_id == worm.id then
          s.ammo = AMMO
        end
      end
    end, { msgs = { wa.msg.START_TURN } })
  end,
}
