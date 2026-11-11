-- The weapon tooltip: a window at the bottom right, seen by the active team's coalition.

local tooltip = {}

local COLOURS = { "red", "blue", "green", "yellow", "purple", "cyan" }
local NOTICE_FRAMES = 150 -- 3 seconds at WA's 50 frames a second
local readers = {}
local installed, window, showing, notice

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
    spec.x, spec.y, spec.align, spec.font = -10, -30, "bottom_right", "medium"
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

function tooltip.hint(id, reader)
  readers[id] = reader
  install()
end

function tooltip.notice(worm, text, seconds)
  install()
  notice = { text = text, alliance = worm.alliance, frames = math.floor((seconds or 3) * 50 + 0.5) }
  if seconds == nil then notice.frames = NOTICE_FRAMES end
  show(text, worm.alliance)
end

return tooltip
