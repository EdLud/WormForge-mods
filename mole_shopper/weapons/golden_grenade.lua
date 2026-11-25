-- Golden Grenade: a charged grenade that bursts into five golden clusters, as the Banana Bomb does.

local holds = require("wf-lib/holds")
local ART = "sprites/golden_grenade/"

return {
  install = function(ctx)
    local bits, bursts, trails = {}, {}, {}
    local bit_sprite
    local function explode(ev)
      local bit = ev.missile and bits[ev.missile]
      if ev.missile then bits[ev.missile], trails[ev.missile] = nil, nil end
      bursts[#bursts + 1] = {x = ev.x, y = ev.y, born = wa.world.frame(), radius = bit and 20 or 30}
    end
    -- Project X's record: the blast, the five clusters and how they fly.
    wa.weapons.replace{
      wep = "weps/golden_grenade.wep", name = "Golden Grenade", panel_icon = ART .. "icon.png",
      sprite = ART .. "body", cluster_sprite = ART .. "fragment", params = {sprite_columns = 1},
      worm_sprites = holds.PX_POSTURE,
      hold = {sheet = ART .. "hold.png", frames = 1, thrown = true,
        hand = holds.PX_HANDS[1], hand_type = 1, hand_scale = 1.2,
        hand_radius = -9.8, hand_rotation = -0.05, hand_radial_rotation = 0.09,
        weap_radial_rotation = 0, weap_rotation = 0.5, weap_radius = -10},
      handling = {remember_selection = false},
      sprites = {ART .. "pixel.png", ART .. "fragment"},
      on_explode = explode,
    }
    local function track_trail(m)
      if m.weapon ~= ctx.id then return end
      if m.phase == "pre" and bits[m.id] == nil then
        bit_sprite = bit_sprite or wa.weapons.data(ctx.id).clusters.bit.sprite
        bits[m.id] = m.sprite == bit_sprite
      end
      if m.phase == "post" then
        trails[m.id] = {x = m.x, y = m.y, frame = wa.world.frame()}
      end
    end
    if not pcall(wa.on.missile_frame, track_trail, { weapons = { ctx.id } }) then wa.on.missile_frame(track_trail) end
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
