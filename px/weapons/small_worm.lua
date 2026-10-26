-- Specialists' Small Worm (PX utility_worm_size, small_worm_script): fired
-- standing still, the worm takes WA's mine shape (a 7x5 block), three
-- quarters of its gravity and half again its mass (PX's SpeedDivider: hits
-- push it less); fired again, or once it stands still after the turn, it is
-- itself again. PX draws the worm's own sprite at 0.85; until we can, the
-- stand-in is a still worm (WA's wbrth1, baked at 0.6), turned the way the
-- worm faces.
local weapon = {}
local ID = "px.small_worm"
local LOOK = "sprites/small_worm/small_worm.png"
-- The baked worm, facing left as WA's sheets do; it stands on the bottom of
-- WA's mine shape (7x5, hotspot (3,2)), centred on the worm.
local LOOK_W, LOOK_H, MASK_BOTTOM = 13, 16, 3
local GRAVITY, MASS = 0.75, 1.5

weapon.definition = {
  copy_from = "stock.double_turn_time",
  name = "Small Worm",
  panel_icon = "sprites/small_worm/small_ico.png",
  handling = { remember_selection = false, ends_turn = false, retreat = -1 },
  utility = { effect = "scripted" },
  sprites = { LOOK },
}
weapon.requires = { "lib/turn_controls" }

function weapon.setup()
  -- Small worms by id; `ending` once a turn has ended (PX's ReadyDeactive).
  local small = {}

  local function activate(worm)
    small[worm.id] = { ending = false }
    worm.y = worm.y - 5
    worm.shape = "mine"
    worm.gravity = worm.gravity * GRAVITY
    worm.mass = worm.mass * MASS
    worm.body_visible = false
    require("lib/weapon_hint").notice(worm, "Small worm mode: ON")
  end

  local function deactivate(worm)
    small[worm.id] = nil
    worm.shape = "worm"
    worm.y = worm.y - 9
    worm.vx, worm.vy = 0, 0
    -- Stuck in land as a full worm: PX's holes free it.
    if not worm:fits(worm.x, worm.y) then
      local x, y = worm.x, worm.y
      for _, h in ipairs({ { 0, -4, 5 }, { -6, 4, 4 }, { 6, 4, 4 }, { -6, 0, 4 }, { 6, 0, 4 }, { 0, -1, 4 } }) do
        wa.land.cut({ x = x + h[1], y = y + h[2], shape = "circle", radius = h[3] })
      end
    end
    worm.gravity = worm.gravity / GRAVITY
    worm.mass = worm.mass / MASS
    worm.body_visible = true
    require("lib/weapon_hint").notice(worm, "Small worm mode: OFF")
  end

  require("lib/turn_controls").register(ID, {
    fire = function(worm)
      -- PX lets it fire only while the worm keeps still.
      if worm.vx ~= 0 or worm.vy ~= 0 then return "eat" end
      if small[worm.id] then deactivate(worm) else activate(worm) end
    end,
  })
  wa.on.turn_end(function()
    for _, s in pairs(small) do s.ending = true end
  end)
  wa.on.worm_message(function(worm)
    local s = small[worm.id]
    if s and s.ending and worm.state == "standing" then deactivate(worm) end
  end, { msgs = { wa.msg.FRAME_FINISH } })
  wa.on.draw(function()
    for _, w in ipairs(wa.worms.all()) do
      if small[w.id] then
        local top, bottom = w.y + MASK_BOTTOM - LOOK_H, w.y + MASK_BOTTOM
        -- The sheet's left edge goes where the worm looks.
        local near, far = w.x - LOOK_W / 2, w.x + LOOK_W / 2
        if w.facing == 1 then near, far = far, near end
        wa.draw.quad({
          points = { { near, top }, { far, top }, { far, bottom }, { near, bottom } },
          sprite = LOOK, depth = wa.depth.WORMS, visibility = w,
        })
      end
    end
  end)
end

return weapon
