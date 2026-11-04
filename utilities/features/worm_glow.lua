-- Worm glow: every worm's body drawn with WA's own colours (a white
-- multiply) and a glow behind it in the add-on's colour, so a worm reads as the light the
-- fog draws round it. WA's poses without a weapon are copied with the
-- match, and the glows of the placed weapons' own worm poses made with it
-- (worm_glow), so none is made mid-match. A worm another pack tints keeps
-- that pack's tint, and gets this one back once the pack clears it.
return function(ctx)
  local pad = ctx.option("pad")
  wa.assets.load({
    wa_sprites = { "worm" },
    worm_glow = {
      radius = ctx.option("radius"),
      pad = pad > 0 and pad or nil,
      gain = ctx.option("gain") / 100,
    },
  })
  local colour = ctx.option("red") * 65536 + ctx.option("green") * 256 + ctx.option("blue")
  local tint = { color = 0xFFFFFF, glow = ctx.option("strength") / 100, glow_color = colour }
  wa.on.draw(function()
    for _, worm in ipairs(wa.worms.all()) do
      if worm.tint == nil then worm.tint = tint end
    end
  end)
end
