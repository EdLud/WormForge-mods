-- A rule set's rules in a window at the top of the screen: open for a few
-- seconds from the first turn, and again at any time with Shift + T, which
-- also shuts the weapon panel. A second Shift + T closes the window. A note
-- above the panel names the key.
--
-- Shift + T opens and closes the window on this machine only, so nothing in
-- the simulation reads whether it is open.

local rules_window = {}

local FRAMES = 500 -- the first turn's window, in game frames
local NOTE = "Shift + T = scheme info"
local NOTE_ROW = 18 -- the note's top, pixels above the panel (Panel highlight's row)
local FADE = 0.25 -- seconds, as the panel slides out

function rules_window.install(lines)
  if not (wa.hud and wa.hud.window and wa.on.hud) then return end
  -- close_at: the frame the first turn's window closes; false once it has,
  -- or once Shift + T took over.
  local window, close_at = nil, nil

  local function open()
    window = wa.hud.window({ lines = lines, align = "top", y = 60, over_panel = false })
  end
  local function close()
    if window then window:close() end
    window = nil
  end

  wa.on.turn_start(function()
    if close_at == nil then
      open()
      close_at = wa.world.frame() + FRAMES
    end
  end)

  local keys = wa.hud.key and wa.panel and wa.panel.stock and true
  if not keys then wa.log("rules window: this WormBench has no wa.hud.key; no Shift + T") end
  local held = false
  wa.on.hud(function()
    if close_at and wa.world.frame() >= close_at then
      close()
      close_at = false
    end
    if not keys then return end
    local panel = wa.panel.stock()
    local down = wa.hud.key("shift") and wa.hud.key("t")
    if down and not held then
      -- An open panel hides the window: shut it and show the rules, even
      -- when the first turn's window is still open behind it.
      local hidden = panel and panel.open
      if window and window:is_open() and not hidden then
        close()
        wa.log("rules window: Shift + T closes the rules")
      else
        if hidden and wa.panel.close then wa.panel.close() end
        if not (window and window:is_open()) then open() end
        wa.log("rules window: Shift + T shows the rules" .. (hidden and ", panel shut" or ""))
      end
      close_at = false
    end
    held = down
    if panel then
      wa.hud.text{
        text = NOTE, x = panel.x + panel.w, y = panel.y - NOTE_ROW, align = "right",
        alpha = math.min(1, panel.opened / FADE),
      }
    end
  end)
end

return rules_window
