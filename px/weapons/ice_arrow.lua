-- Ice Arrow: an arrow that freezes the worm it hits.

local weapon = {}
local ID = "px.ice_arrow"
local ARROW = "sprites/ice_arrow/arrow.png"

weapon.record = {
  handling = {
    remember_selection = true,
    ends_turn = true,
  },
}

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    wep = "weps/armageddon.wep",
    panel_icon = "sprites/ice_arrow/icon.png",
    sprites = { ARROW },
    worm_sprites = {
      wbowlnk = "sprites/ice_arrow/wbowlnk.png",
      wbowlnku = "sprites/ice_arrow/wbowlnku.png",
      wbowlnkd = "sprites/ice_arrow/wbowlnkd.png",
      wbowbk2 = "sprites/ice_arrow/wbowbk2.png",
      wbowbk2u = "sprites/ice_arrow/wbowbk2u.png",
      wbowbk2d = "sprites/ice_arrow/wbowbk2d.png",
      wbow = "sprites/ice_arrow/wbow.png",
      wbowu = "sprites/ice_arrow/wbowu.png",
      wbowd = "sprites/ice_arrow/wbowd.png",
      wbowp = "sprites/ice_arrow/wbowp.png",
      wbowpu = "sprites/ice_arrow/wbowpu.png",
      wbowpd = "sprites/ice_arrow/wbowpd.png",
      wbowf = "sprites/ice_arrow/wbowf.png",
      wbowfu = "sprites/ice_arrow/wbowfu.png",
      wbowfd = "sprites/ice_arrow/wbowfd.png",
    },
  })
end

function weapon.setup()
  local shared = require("lib/shared")
  local pending = {} -- stable worm id -> freeze on that worm's next frame

  wa.on.hurt(function(hit)
    if hit.phase == "post" and hit.source_weapon == ID
      and hit.kind == "arrow" then
      pending[hit.worm.id] = true
    end
  end)

  wa.on.worm_message(function(worm)
    if pending[worm.id] then
      pending[worm.id] = nil
      worm:freeze()
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })

  -- Planted, WA writes the arrow into the land in its own colours; the icy
  -- frame goes over the same pixels, its colours shown on the GPU layer.
  if wa.on.arrow_land then
    wa.on.arrow_land(function(ev)
      if ev.weapon == ID then
        wa.land.stamp{ sprite = ARROW, frame = ev.frame, x = ev.x // 1, y = ev.y // 1, true_colour = true }
      end
    end)
  end

  -- In flight, PX draws WA's arrow icy, through
  -- SetColorMod(ARGB(180, 20, 90, 170), 8), twice on every tenth game frame.
  -- The colour is baked into the sheet (tools/export_ice_arrow_sprite.py).
  if wa.on.draw then
    local DEPTH = 0x50001 -- the depth WA draws arrows at (ArrowEntity::render)
    local ICE = 0xB4FFFFFF -- PX's 180 opacity
    local brush = wa.draw.brush{ sprite = ARROW, depth = DEPTH }
    wa.on.draw(function()
      local twice = wa.world.frame() % 10 == 0
      for _, a in ipairs(wa.arrows.all()) do
        if a.weapon == ID then
          if a.visible then a.visible = false end
          brush:box(a.x, a.y, 60, 60, 0, a.frame, ICE)
          if twice then brush:box(a.x, a.y, 60, 60, 0, a.frame, ICE) end
        end
      end
    end)
  end
end

return weapon
