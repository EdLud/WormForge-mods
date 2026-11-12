-- Weather: rain, a stormy sky, rings on water and puddles, and lightning.
local L = require("wf-lib/lightning")

local RAIN_SOUND = "sounds/rain.wav"

return function(ctx)
  local cfg = {
    rain = ctx.option("rain") / 100,
    wind = ctx.option("wind") / 100,
    clouds = ctx.option("clouds") / 100,
    darkness = ctx.option("darkness") / 100,
    ripples = ctx.option("ripples"),
    chance = ctx.option("lightning_chance"),
    strike = ctx.option("lightning_effect") == "strike",
    volume = ctx.option("volume") / 100,
  }
  local sprites = { "sprites/rain.png", "sprites/splash.png", "sprites/ring.png", "sprites/oval.png", "sprites/flat.png" }
  for _, path in ipairs(L.SPRITES) do sprites[#sprites + 1] = path end
  local sounds = { RAIN_SOUND }
  for _, path in ipairs(L.SOUNDS) do sounds[#sounds + 1] = path end
  wa.assets.load({ sprites = sprites, sounds = sounds })

  require("lib/sim").install(cfg)
  if not (wa.on.draw and wa.draw.quads and wa.draw.ribbon) then return end
  L.setup()
  local draws = {}
  for _, name in ipairs({ "lib/sky", "lib/rain", "lib/surface" }) do
    draws[#draws + 1] = require(name).install(cfg)
  end

  local st = {}
  local sound
  wa.on.draw(function()
    local v = wa.world.view()
    if v.w <= 0 or v.h <= 0 then return end
    local z = v.zoom > 0 and v.zoom or 1
    local hw, hh = v.w / z / 2, v.h / z / 2
    st.cx, st.cy, st.zoom = v.cx, v.cy, z
    st.left, st.right, st.top, st.bottom = v.cx - hw, v.cx + hw, v.cy - hh, v.cy + hh
    st.w, st.h = 2 * hw, 2 * hh
    st.now = wa.world.frame() + wa.draw.fraction()
    st.wind = wa.world.wind()
    st.water = wa.world.water()
    if not sound and wa.sound.ambient and cfg.rain > 0 and cfg.volume > 0 then
      sound = wa.sound.ambient({ path = RAIN_SOUND, volume = math.min(1, cfg.volume * (0.4 + 0.6 * cfg.rain)), fade_ms = 3000 })
    end
    for _, draw in ipairs(draws) do draw(st) end
  end)
end
