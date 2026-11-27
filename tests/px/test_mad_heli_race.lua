-- From the mods root: lua tests/px/test_mad_heli_race.lua
-- The rules window's keys and timing are tested with Team17's rules
-- (test_team17.lua); this checks Mad Heli Race opens it with its own lines.
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local windows, on = {}, { turn_start = {}, hud = {} }
wa = {
  log = function() end,
  world = { frame = function() return 0 end },
  hud = {
    key = function() return false end,
    text = function() end,
    window = function(spec)
      local w = { spec = spec, open = true }
      function w:close() self.open = false end
      function w:is_open() return self.open end
      windows[#windows + 1] = w
      return w
    end,
  },
  panel = { stock = function() return nil end, close = function() end },
  on = {},
}
for name, list in pairs(on) do wa.on[name] = function(f) list[#list + 1] = f end end

require("components/mad_heli_race").install({})
for _, f in ipairs(on.turn_start) do f({}) end

local lines = windows[1] and windows[1].spec.lines or {}
local text = {}
for i, l in ipairs(lines) do text[i] = l[1] end
check("the rules window opens at the first turn", #windows == 1 and windows[1].open)
check("its lines are Mad Heli Race's", table.concat(text, " / ") ==
  "Mad Heli Race / Big Rope Race maps recommended / One Bullet Time per turn / Shift to Dash",
  table.concat(text, " / "))
check("Shift + T is wired", #on.hud == 1)

if failed > 0 then
  print(failed .. " Mad Heli Race check(s) failed")
  os.exit(1)
end
print("Mad Heli Race passed")
