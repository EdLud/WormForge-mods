-- A custom icon in the stock weapon panel.
--
-- `panel_icon` takes a pack PNG. A full 32x32 icon image -- every Project X
-- weapon icon is one -- is used as is: the panel shows its 24x24 centre, as it
-- does for WA's own icons. A smaller PNG is centred in that window instead.
-- Colours are matched to the ones WA's own icons use, and the greyed-out
-- frame is derived the way theirs is, so it looks native in both states.
--
-- This icon is PX's Hellish Hand Grenade, copied byte for byte, so replays
-- refer to it by hash in the public store instead of embedding it.
return {
  install = function()
    wa.weapons.replace({
      copy_from = "stock.holy_grenade",
      name = "Hellish Hand Grenade",
      panel_icon = "panel_icon/hhh_ico.png",
    })
  end,
}
