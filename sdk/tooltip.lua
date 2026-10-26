-- A bundle's weapon tooltip: one window in WA's small font at the bottom
-- right of the screen, just above the wind bar, bordered in the active team's
-- colour and seen by that team's coalition only. WormForge fades it out
-- while WA's weapon panel is open.
--
--   local tooltip = require("wf-lib/tooltip")
--   -- While the turn's worm holds the weapon: its settings, live.
--   tooltip.hint("my.weapon", function(worm) return "My Weapon: " .. mode .. "\n+ next mode" end)
--   -- Something that just happened: shown for a few seconds over the hint.
--   tooltip.notice(worm, "No space to launch!")
--
-- A reader returns the text (`\n` breaks lines) or nil for none; it runs on
-- every frame the weapon is held, so the window follows its settings. The
-- window is opened, changed and closed by the simulation, the same on every
-- machine; only who sees it differs.
local tooltip = {}

local COLOURS = { "red", "blue", "green", "yellow", "purple", "cyan" }
local NOTICE_FRAMES = 150 -- 3 seconds at WA's 50 frames a second
local readers = {}
local installed, window, showing, notice

-- WA's top banner, for an engine without `wa.hud.window`: one line.
local function banner(text, alliance)
  local line = text:gsub("\n", " | ")
  if #line > 127 then line = line:sub(1, 124) .. "..." end
  wa.hud.message_top(line, { to = "coalition", alliance = alliance })
end

local function show(text, alliance)
  local key = alliance .. "\0" .. text
  if key == showing then return end
  showing = key
  if not wa.hud.window then return banner(text, alliance) end
  local spec = { text = text, border = COLOURS[alliance + 1] or "grey", to = "coalition", alliance = alliance }
  if window then
    window:set(spec)
  else
    spec.x, spec.y, spec.align, spec.font = -10, -30, "bottom_right", "small"
    window = wa.hud.window(spec)
  end
end

local function close()
  if window then window:close() end
  window, showing = nil, nil
end

local function install()
  if installed then return end
  installed = true
  wa.on.worm_message(function(worm)
    if not worm.turn then return end
    if notice then
      notice.frames = notice.frames - 1
      if notice.frames >= 0 then return show(notice.text, notice.alliance) end
      notice = nil
    end
    local reader = worm.hp > 0 and readers[worm.weapon]
    local text = reader and reader(worm)
    if text then show(text, worm.alliance) else close() end
  end, { msgs = { wa.msg.FRAME_FINISH } })
  local function reset() notice = nil; close() end
  wa.on.turn_start(reset)
  wa.on.turn_end(reset)
end

-- `reader(worm)` is the weapon `id`'s tooltip while the turn's worm holds it.
function tooltip.hint(id, reader)
  readers[id] = reader
  install()
end

-- `text` for `worm`'s coalition now, for `seconds` (3) of the turn.
function tooltip.notice(worm, text, seconds)
  install()
  notice = { text = text, alliance = worm.alliance, frames = math.floor((seconds or 3) * 50 + 0.5) }
  if seconds == nil then notice.frames = NOTICE_FRAMES end
  show(text, worm.alliance)
end

return tooltip
