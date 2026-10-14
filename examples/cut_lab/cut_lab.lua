-- Cut Lab: the Bazooka cuts a hole of the chosen shape where it lands.
-- + cycles the shape; 1-9 and 0 set the size (0 is the biggest).

-- Each shape, and how a size from 1 to 10 sizes it.
local SHAPES = {
  { name = "circle", cut = function(x, y, size)
      wa.land.cut({ x = x, y = y, shape = "circle", radius = size * 8 })   -- 8..80 px
    end },
  { name = "drill", cut = function(x, y)
      wa.land.cut({ x = x, y = y, shape = "drill" })                     -- WA's own; one size
    end },
  { name = "torch", cut = function(x, y, _, worm)
      wa.land.cut({ x = x, y = y, shape = "torch", facing = worm and worm.facing or 1, angle = 0 })
    end },
  { name = "star", cut = function(x, y, size)
      wa.land.cut({ x = x, y = y, shape = "sprite", sprite = "sprites/star", frame = size - 1 })
    end },
  { name = "ring", cut = function(x, y, size)                             -- its middle stays
      wa.land.cut({ x = x, y = y, shape = "sprite", sprite = "sprites/ring", frame = size - 1 })
    end },
}

local shape, size = 1, 5
local plus_was, digit_was = false, nil

-- The turn's worm reads the keys once a frame: synced keys, so every
-- player's game changes shape and size at the same moment.
wa.on.worm_message(function(worm)
  if not worm.turn then return end
  local keys = wa.world.keys()
  if keys.plus_key and not plus_was then
    shape = shape % #SHAPES + 1
  end
  plus_was = keys.plus_key
  if keys.digit and keys.digit ~= digit_was then
    size = keys.digit == 0 and 10 or keys.digit
  end
  digit_was = keys.digit
end, { msgs = { wa.msg.FRAME_FINISH } })

wa.weapons.replace({
  weapon = "bazooka",
  copy_from = "bazooka",
  name = "Cut Lab",
  patch = { damage = 1, blast = 1 },       -- WA's own blast barely scratches
  sprites = { "sprites/star", "sprites/ring" },
  on_explode = function(ev)
    SHAPES[shape].cut(ev.x, ev.y, size, ev.worm)
    wa.log(("cut lab: %s, size %d at %d,%d"):format(SHAPES[shape].name, size, ev.x // 1, ev.y // 1))
  end,
})

wa.on.hud(function()
  wa.hud.line(("Cut Lab: %s, size %d   (+ shape, 1-9/0 size)"):format(SHAPES[shape].name, size), 14, 40)
end)
