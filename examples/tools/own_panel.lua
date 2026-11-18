-- Own panel: a weapon panel drawn in Lua in place of the stock one, to try wa.panel.replace,
-- mouse, capture and select, and wa.hud.sprite, rect and text. The right click opens and
-- shuts it. While it is open the mouse moves its cursor, and a left click picks the weapon
-- under it. Its rows and columns are the panel places of the profile (wa.panel.layout).

local CELL, GAP = 28, 2
local RIGHT, BOTTOM = 11, 23
local ROWS = { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "utility" }

local BLACK, GREY, YELLOW, WHITE = 0xFF000000, 0xFF9C9D9C, 0xFFFCFE80, 0xFFFFFFFF

return function()
  local open = false
  local replaced = false
  -- The rows with weapons, each { id per column }, and the columns of the widest row.
  local grid, columns = {}, 0

  local function lay_out()
    local layout = wa.panel.layout()
    local by_row = {}
    for _, id in ipairs(wa.sorted(layout)) do
      local p = layout[id]
      by_row[p.row] = by_row[p.row] or {}
      by_row[p.row][p.column] = id
    end
    grid, columns = {}, 0
    for _, row in ipairs(ROWS) do
      local cells = by_row[row]
      if cells then
        local last = 0
        for column in pairs(cells) do last = math.max(last, column) end
        grid[#grid + 1] = cells
        columns = math.max(columns, last)
      end
    end
  end

  local function turn_worm()
    for _, worm in ipairs(wa.worms.all()) do
      if worm.turn then return worm end
    end
  end

  -- The stock panel leaves out a weapon the team has run out of.
  local function shown(worm, id)
    return worm and worm:ammo(id) ~= 0
  end

  local function box(x, y, w, h, edge)
    wa.hud.rect{ x = x, y = y, w = w, h = h, color = edge }
    wa.hud.rect{ x = x + 1, y = y + 1, w = w - 2, h = h - 2, color = BLACK }
  end

  local function icon(id, x, y, greyed)
    local v = wa.weapons.visual(id)
    if not v then return end
    -- The middle 24x24 of the icon, as the stock panel shows it.
    local w, h = math.min(v.width, 24), math.min(v.height, 24)
    wa.hud.sprite{
      sprite = v.sprite, frame = v.frame, x = x + (24 - w) // 2, y = y + (24 - h) // 2,
      part = { x = (v.width - w) // 2, y = (v.height - h) // 2, w = w, h = h },
      color = greyed and 0xFF606060 or WHITE,
    }
  end

  local function cursor(x, y)
    wa.hud.rect{ x = x - 4, y = y - 1, w = 9, h = 3, color = BLACK }
    wa.hud.rect{ x = x - 1, y = y - 4, w = 3, h = 9, color = BLACK }
    wa.hud.rect{ x = x - 3, y = y, w = 7, h = 1, color = WHITE }
    wa.hud.rect{ x = x, y = y - 3, w = 1, h = 7, color = WHITE }
  end

  wa.on.turn_start(function()
    -- Only with a profile that places weapons: without one the stock panel stays.
    if not replaced and next(wa.panel.layout()) then
      replaced = wa.panel.replace()
      wa.log(replaced and "own_panel: the stock panel is replaced" or "own_panel: this DLL can't replace the stock panel")
    end
    open = false
  end)

  wa.on.hud(function()
    if not replaced then return end
    local mouse = wa.panel.mouse()
    if mouse.right then
      open = not open
      if open then lay_out() end
    end
    if not open or columns == 0 then return end
    wa.panel.capture()

    local sw, sh = wa.hud.size()
    local w = columns * (CELL + GAP) - GAP
    local h = #grid * (CELL + GAP) - GAP
    local left, top = sw - RIGHT - w, sh - BOTTOM - h
    local worm = turn_worm()
    local hovered
    box(left - 4, top - 4, w + 8, h + 8, GREY)
    for r, cells in ipairs(grid) do
      for c = 1, columns do
        local id = cells[c]
        local x, y = left + (c - 1) * (CELL + GAP), top + (r - 1) * (CELL + GAP)
        local over = mouse.x >= x and mouse.x < x + CELL and mouse.y >= y and mouse.y < y + CELL
        if id and shown(worm, id) then
          if over then hovered = id end
          local delay = worm:delay(id)
          box(x, y, CELL, CELL, over and YELLOW or GREY)
          icon(id, x + 2, y + 2, delay > 0)
          local ammo = worm:ammo(id)
          if ammo > 0 then
            wa.hud.text{ text = tostring(ammo), x = x + CELL - 3, y = y + CELL - 9, font = "small", align = "right" }
          end
          if delay > 0 then
            wa.hud.text{ text = tostring(delay), x = x + 3, y = y + 3, font = "small", color = "red" }
          end
        end
      end
    end
    if hovered then
      wa.hud.text{ text = hovered, x = left + w, y = top - 18, align = "right" }
      if mouse.left and wa.panel.select(hovered) then open = false end
    end
    cursor(mouse.x, mouse.y)
  end)
end
