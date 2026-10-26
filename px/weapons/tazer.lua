-- One chain-lightning shot per team turn, sharing the existing electrical arc.
local weapon = {}
local available=true
weapon.definition = {
  copy_from="stock.handgun",
  name="Tazer",
  panel_icon="sprites/tazer/ico_tazer.png",
  fires={subtype=8},
  handling={remember_selection=false,ends_turn=false,retreat=3000},
  gun={bullets=1,impact_effect=3,shot_interval_ms=0,spread_deg=25,
    explosion={bias=20,push_pct=100}},
  worm_sprites={
    weaponlnk="sprites/tazer/wtazlnk.png",weaponlnku="sprites/tazer/wtazlnku.png",
    weaponlnkd="sprites/tazer/wtazlnkd.png",wthrow="sprites/tazer/wtazer.png",
    wthrowu="sprites/tazer/wtazeru.png",wthrowd="sprites/tazer/wtazerd.png",
    weaponfire="sprites/tazer/wtazer.png",weaponfireu="sprites/tazer/wtazeru.png",
    weaponfired="sprites/tazer/wtazerd.png",
  },
  sprites={"sprites/lightning/beam.png","sprites/lightning/glow.png","sprites/lightning/cloud.png",
    "sprites/electric_grenade/explosion.png","sprites/electric_grenade/tazed1.png",
    "sprites/electric_grenade/tazed2.png"},
  sounds={"sounds/lightning/tazer_loop.wav"},
  params={gpu_prefix="sprites/"},
  on_fire=function(ev)
    if not available then return end
    available=false
    local worm=ev.worm
    local angle=(1-worm.aim)*math.pi
    if worm.facing<0 then angle=2*math.pi-angle end
    local dx,dy=wa.math.sin(angle),-wa.math.cos(angle)
    require("lib/electrical").context().start_arc{
      x=worm.x+4*dx,y=worm.y+4*dy,dx=dx,dy=dy,worm=worm,ignore={worm},burst=false,
    }
  end,
}
weapon.requires={"weapons/electric_grenade","lib/electrical"}
function weapon.setup()
  available=true
  wa.on.worm_message(function(worm,msg)
    if msg==wa.msg.TURN_STARTED then available=true
    elseif msg==wa.msg.FIRE_WEAPON and worm.turn and worm.weapon=="px.tazer" then
      if not available then return "eat" end
    end
  end,{msgs={wa.msg.TURN_STARTED,wa.msg.FIRE_WEAPON}})
  require("lib/weapon_hint").register("px.tazer",function()
    return available and "Tazer\nSpace: a chaining electric arc" or "Tazer\nUsed this turn"
  end)
end
return weapon
