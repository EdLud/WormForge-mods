-- From the repository root: lua mods/utilities/test_panel_highlight.lua
local root = UTILITIES_ROOT or "mods/utilities/"

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

-- The panel as wa.panel.stock() gives it, and what the HUD draws.
local hud, panel, rects, texts
local records = {
  ["stock.ninja_rope"] = { handling = { ends_turn = false } },
  ["stock.bazooka"] = { handling = { ends_turn = true } },
}
wa = {
  on = { hud = function(f) hud = f end },
  panel = { stock = function() return panel end },
  weapons = { data = function(id)
    local r = records[id]
    if not r then error("weapons.data: " .. id .. " is not on the panel this match") end
    return r
  end },
  hud = {
    rect = function(t) rects[#rects + 1] = t end,
    text = function(t) texts[#texts + 1] = t end,
  },
  log = function() end,
}
dofile(root .. "features/panel_highlight.lua")()

local function frame(opened)
  rects, texts = {}, {}
  panel = opened and {
    x = 500, y = 300, w = 177, h = 159, open = true, opened = opened,
    cells = {
      { weapon = "stock.bazooka", x = 533, y = 304, size = 24 },
      { weapon = "stock.ninja_rope", x = 562, y = 333, size = 24 },
      { weapon = "px.missing", x = 591, y = 333, size = 24 },
    },
  } or nil
  hud()
end

-- Shut: nothing drawn.
frame(nil)
check("shut panel draws nothing", #rects == 0 and #texts == 0, #rects)

-- Open: the rope's four sides and the key's four, with the key's text.
frame(1)
check("one outlined cell and the key", #rects == 8, #rects)
check("the rope's outline is round its icon", rects[1].x == 560 and rects[1].y == 331 and rects[1].w == 28, rects[1].x)
check("the key sits above the panel, at the first column", rects[5].x == 531 and rects[5].y < 300, rects[5].y)
check("the key text", #texts == 1 and texts[1].text == " = sdet", texts[1] and texts[1].text)
check("fully faded in", rects[1].color >> 24 == 255 and texts[1].alpha == 1, rects[1].color)

-- Halfway into the fade.
frame(0.125)
check("half faded", rects[1].color >> 24 == 127 and math.abs(texts[1].alpha - 0.5) < 1e-9, rects[1].color >> 24)
check("green", rects[1].color & 0xFFFFFF == 0x40E040, string.format("%x", rects[1].color))

-- A weapon whose record can't be read isn't highlighted, and is asked again.
records["px.missing"] = { handling = { ends_turn = false } }
frame(1)
check("a record readable later is highlighted then", #rects == 12, #rects)

if failed > 0 then
  print(("panel highlight: %d failed"):format(failed))
  os.exit(1)
end
print("panel highlight: ok")
