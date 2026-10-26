-- Four scripted secondary grenades with independent linear blasts.
local holds = require("wf-lib/holds")
local ART = "sprites/golden_grenade/"
local CHILD = {
  collision_shape = 2, animation = 1, speed_pct = 100, wind_pct = 0, gravity_pct = 100,
  countdown = 0, fuse = 8000, flight_sound = 0, explode_on_space = false,
  action = "none", burst = "nothing", impact_particles = false,
  ends_on_contact = {land = true, worms = true, worms_frozen = true,
    crates = true, donor_cards = true, objects = true},
  explosion = {power = 0, push_pct = 0, bias = 0},
  explosion_sound = {enabled = false},
  trail = {sprite = 0, power = 0, speed = 0},
}

return {
  install = function(ctx)
    local children, parents, bursts, trails = {}, {}, {}, {}
    local launching_children = 0
    local function explode(ev)
      local child = children[ev.missile] or (launching_children > 0 and not parents[ev.missile])
      children[ev.missile], parents[ev.missile], trails[ev.missile] = nil, nil, nil
      local damage, push, reach = child and 60 or 90, child and 100 or 60, child and 124 or 184
      -- The explosion point needs its own emitter, independent of whether
      -- the throwing worm survives. Persisting effects do not hold the turn.
      local sound_owner = ev.worm
      if not sound_owner or sound_owner.id == 0 then sound_owner = wa.worms.all()[1] end
      if sound_owner then
        local born = wa.world.frame()
        local speaker = wa.actors.spawn{sprite = false, owner = sound_owner,
          x = ev.x, y = ev.y, gravity = false, collide = false, solid = false, persist = true,
          on = function(a)
            if wa.world.frame() - born >= 150 then a:despawn() end
          end}
        wa.sound.play(speaker, wa.random(69, 71))
      end
      wa.world.blast{x = ev.x, y = ev.y, owner = ev.worm,
        damage = damage, radius = reach, push_pct = push, terrain_radius = damage}
      bursts[#bursts + 1] = {x = ev.x, y = ev.y, born = wa.world.frame(), radius = child and 20 or 30}
      if child then return end
      -- Spawn after the parent's blast. PX's evenly spaced 15-degree upward fan.
      CHILD.sprite = wa.weapons.data(ctx.id).clusters.bit.sprite
      for i = 0, 3 do
        local radians = (-97.5 + i * 5) * math.pi / 180
        launching_children = launching_children + 1
        local ok, id = pcall(wa.weapons.launch, {weapon = ctx.id, owner = ev.worm,
          x = ev.x, y = ev.y - 20, vx = wa.math.cos(radians) * 10, vy = wa.math.sin(radians) * 10,
          missile = CHILD})
        launching_children = launching_children - 1
        if ok and id then children[id] = true
        elseif not ok then wa.log("Golden Grenade: secondary launch failed: " .. tostring(id)) end
      end
    end
    wa.weapons.replace{
      copy_from = "stock.grenade", name = "Golden Grenade", panel_icon = ART .. "icon.png",
      sprite = ART .. "body", cluster = {sprite = ART .. "fragment"}, params = {sprite_columns = 1},
      worm_sprites = holds.PX_POSTURE,
      hold = {sheet = ART .. "hold.png", frames = 1, thrown = true,
        hand = holds.PX_HANDS[1], hand_type = 1, hand_scale = 1.2,
        hand_radius = -9.8, hand_rotation = -0.05, hand_radial_rotation = 0.09,
        weap_radial_rotation = 0, weap_rotation = 0.5, weap_radius = -10},
      handling = {remember_selection = false},
      sprites = {ART .. "pixel.png", ART .. "fragment"},
      missile = {burst = "nothing", impact_particles = false,
        explosion = {power = 0, push_pct = 0, bias = 0},
        explosion_sound = {enabled = false}, trail = {sprite = 0, speed = 0}},
      on_explode = explode,
    }
    -- Resolve the secondary art via a weapon-scoped native cluster sheet. The
    -- parent creates no native clusters; secondary launches use that sheet id.
    wa.on.missile_frame(function(m)
      if m.weapon ~= ctx.id then return end
      if m.phase == "pre" and not children[m.id] then parents[m.id] = true end
      if m.phase == "post" then
        trails[m.id] = {x = m.x, y = m.y, frame = wa.world.frame()}
      end
    end)
    wa.on.draw(function()
      local now = wa.world.frame()
      for _, id in ipairs(wa.sorted(trails)) do
        local p = trails[id]
        if now - p.frame > 2 then trails[id] = nil
        else
          wa.draw.quad{sprite = ART .. "pixel.png", depth = wa.depth.OBJECTS, color = 0xFFFFE61E,
            blend = "add", points = {{p.x-1,p.y-1},{p.x+1,p.y-1},{p.x+1,p.y+1},{p.x-1,p.y+1}}}
        end
      end
      for i = #bursts, 1, -1 do
        local p = bursts[i]
        local age = now - p.born
        if age >= 10 then table.remove(bursts, i)
        else
          local points, alpha = {}, math.floor(255 * (1 - age / 10))
          for n = 0, 24 do
            local angle = n * math.pi / 12
            points[#points + 1] = {x = p.x + math.cos(angle) * p.radius,
              y = p.y + math.sin(angle) * p.radius, width = 30 * (1 - age / 10),
              color = (alpha << 24) | 0xFFE61E, u = n / 24}
          end
          wa.draw.ribbon{sprite = ART .. "pixel.png", depth = wa.depth.OBJECTS, blend = "add", points = points}
        end
      end
    end)
  end,
}
