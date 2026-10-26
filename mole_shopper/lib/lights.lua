-- Source coalition colours. The light and body have independent lifetimes:
-- neither a turn change nor the planter's death extinguishes a placed light.
local colours = {0xE62828, 0x0087E6, 0x63E63C, 0xE6E653, 0xAD45E6, 0x3EE6E6}
local M = {}

function M.colour(worm)
  return colours[(worm.alliance or 0) + 1] or 0xFFFFFF
end

function M.attach(actor, radius, terrain_blocking)
  actor.light = {
    circle = radius,
    cone = {length = 0},
    shadow_cast = terrain_blocking ~= false,
    seen_by = "owner",
    discover = false,
  }
end

return M
