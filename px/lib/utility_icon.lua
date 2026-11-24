-- A utility's icon in the utility tray above the wind bar (`wa.hud.utilities`) while it's in effect.
-- On a DLL without the tray, these calls do nothing.

local icon = {}
local open = {} -- weapon id -> { key -> entry }

local function key(who)
  return type(who) == "number" and "team " .. who or "worm " .. who.id
end

-- `who` is a worm (shown while it has the turn) or a team number (shown on its turn).
function icon.on(id, who)
  local tray = wa.hud and wa.hud.utilities
  if not tray then return end
  local entries = open[id] or {}
  open[id] = entries
  local k = key(who)
  if entries[k] and entries[k]:is_open() then return end
  entries[k] = tray.add(type(who) == "number" and { weapon = id, team = who } or { weapon = id, worm = who })
end

function icon.off(id, who)
  local entries = open[id]
  local entry = entries and entries[key(who)]
  if entry then
    entry:remove()
    entries[key(who)] = nil
  end
end

function icon.off_all(id)
  for _, entry in pairs(open[id] or {}) do entry:remove() end
  open[id] = nil
end

return icon
