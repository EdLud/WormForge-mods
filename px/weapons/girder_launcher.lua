-- Four mini-girders: push a struck body, otherwise become permanent terrain.
local holds = require("wf-lib/holds")
local weapon = {}
local launch, impact
weapon.definition = {
  copy_from = "stock.bazooka",
  name = "Girder Launcher",
  panel_icon = "sprites/girder_launcher/ico_girderl.png",
  sprite = "bazooka",
  fires = {launch_power_pct=45},
  handling = {remember_selection=false,shots=4,ends_turn=false,retreat=3000},
  missile = {
    flight_sound=95,fuse=4200,gravity_pct=0,wind_pct=0,impact_particles=true,
    bounce = {
      bounciness=80,contact_sides=0,max_bounces=40,sound=110,terrain_keep_speed_pct=80,
      hits={crates=true,donor_cards=true,objects=true,water=true,worms_frozen=true},
    },
    ends_on_contact={land=true,mines=true,water=true,worms=true},
    explosion={power=0,push_pct=0},
    trail={power=25,speed=250,sprite="sprites/girder_launcher/trail.png"},
  },
  worm_sprites=holds.PX_POSTURE,
  sprites={"sprites/girder_launcher/mgirderspb.png","sprites/girder_launcher/mgirder.png",
    "sprites/girder_launcher/laser.png"},
  sounds={"sounds/girder_launcher/mgirder_impact.wav"},
  params={gpu_prefix="sprites/girder_launcher/"},
  hold={
    sheet="sprites/girder_launcher/spb_girderl.png",frames=8,draw_hand=false,
    animate=true,anim_speed=1,hand_radius=0,hand_rotation=0,hand_radial_rotation=0,
    weap_radial_rotation=1,weap_rotation=1,weap_radius=0,
  },
  on_fire=function(ev) launch(ev) end,
  on_explode=function(ev) impact(ev) end,
}
weapon.missile_sprite={sheet="sprites/girder_launcher/mgirderspb.png",hide=true,
  frames=8,animate=true,anim_speed=3}

-- The girder: a 22 x 8 bar centred where the shell stops, along its flight
-- (mgirder.png's 32 frames, measured: 11 px each way along, 4 across).
local HALF_LENGTH, HALF_WIDTH = 11, 4
-- A worm's box, WA's worm shape (9 x 16), around its position.
local WORM_HALF_W, WORM_HALF_H = 4.5, 8
-- WA starts the shell this far from the worm along its aim (logged: 14.0).
local LAUNCH_OFFSET = 14
-- The shell flies straight (no gravity, no wind) for its 4.2 s fuse.
local REACH = 2400

-- Whether a girder laid at (x, y) along the unit (dx, dy) covers `worm`.
local function covers(x, y, dx, dy, worm)
  for s = -HALF_LENGTH, HALF_LENGTH do
    local ox = math.max(math.abs(x + s * dx - worm.x) - WORM_HALF_W, 0)
    local oy = math.max(math.abs(y + s * dy - worm.y) - WORM_HALF_H, 0)
    if ox * ox + oy * oy <= HALF_WIDTH * HALF_WIDTH then return true end
  end
  return false
end

-- What the shell does where it stops: a body within 20 px is pushed and no
-- girder is laid (the shooter excepted); else the girder is laid.
local function pushed(x, y, shooter)
  for _, o in ipairs(wa.world.electrical_nearby(x, y, 29, false)) do
    if (o.kind == "worm" or o.kind == "mine" or o.kind == "crate" or o.kind == "oil")
      and not (o.kind == "worm" and o.id == shooter)
      and math.abs(o.x - x) < 20 and math.abs(o.y - y) < 20 then
      return o
    end
  end
end

-- The worm a girder laid at (x, y) along (dx, dy) would trap, if any.
local function trapped(x, y, dx, dy, shooter)
  if pushed(x, y, shooter) then return nil end
  for _, worm in ipairs(wa.worms.all()) do
    if covers(x, y, dx, dy, worm) then return worm end
  end
end

-- A girder that would trap a worm is not laid: WA's "can't fire" sound.
local function deny(worm)
  wa.sound.play(worm, 120)
end

function weapon.setup()
  local flights, launching = {}, nil
  local turrets = require("lib/turret")
  -- At the fire press, before WA counts the shot: where the girder would
  -- land, from the aim. One that would trap a worm (the shooter beside a
  -- wall) is refused, so the shot stays the shooter's to fire elsewhere.
  wa.on.worm_message(function(worm)
    if not (worm.turn and worm.hp > 0 and worm.weapon == "px.girder_launcher") then return end
    local angle = (1 - worm.aim) * math.pi
    if worm.facing < 0 then angle = 2 * math.pi - angle end
    local dx, dy = math.sin(angle), -math.cos(angle)
    local x0, y0 = worm.x + LAUNCH_OFFSET * dx, worm.y + LAUNCH_OFFSET * dy
    local hit = wa.world.trace{x0 = x0, y0 = y0, x1 = x0 + REACH * dx, y1 = y0 + REACH * dy,
      radius = 2, with = {"terrain", "worms", "mines", "crates", "oil"}, ignore = {worm}}
    if not hit or hit.obj then return end
    local x, y = hit.x, hit.y
    if hit.starts_solid then x, y = x0, y0 end
    if trapped(x, y, dx, dy, worm.id) then
      deny(worm)
      return "eat"
    end
  end, { msgs = { wa.msg.FIRE_WEAPON } })
  launch = function(ev)
    local flight={ev.vx,ev.vy,shooter=ev.worm.id}
    local previous=launching
    launching=flight
    local ok,id=pcall(wa.weapons.launch,{
      weapon="px.girder_launcher",owner=ev.worm,x=ev.x,y=ev.y,vx=ev.vx,vy=ev.vy,
    })
    launching=previous
    if not ok then error(id) end
    if id and not flight.exploded then flights[id]=flight end
  end
  wa.on.missile_frame(function(m)
    if m.weapon ~= "px.girder_launcher" then return end
    local flight=flights[m.id]
    if flight then flight[1],flight[2],flight.uid=m.vx,m.vy,m.uid end
  end)
  local function orientation(vx,vy)
    if vx==0 then return vy>0 and 16 or 0 end
    if vy==0 then return vx>0 and 8 or 24 end
    -- PX's ratio bins; these do not divide the circle into equal angles.
    if vx>0 and vy<0 then return math.min(math.floor(3*vx/-vy),7) end
    if vx>0 then return math.min(math.floor(8+3*vy/vx),15) end
    if vy>0 then return math.min(math.floor(16+3*-vx/vy),23) end
    return math.min(math.floor(24+3*-vy/-vx),31)
  end
  impact = function(ev)
    local flight=(ev.missile and flights[ev.missile]) or launching
    if ev.missile then flights[ev.missile]=nil end
    if flight then flight.exploded=true end
    local vx,vy=flight and flight[1] or 0,flight and flight[2] or 0
    local o=pushed(ev.x,ev.y,flight and flight.shooter)
    if o then
      o.vx,o.vy=vx/4,vy/4
      if o.kind=="worm" then o:hurt(3)
      else o:hit(3,vx/2,vy/2,"projectile") end
      return
    end
    local sentry=turrets.projectile_target(ev.x,ev.y)
    if sentry and turrets.projectile_hit(sentry,3,vx/4,vy/4,flight and flight.uid) then return end
    -- Where the press's forecast missed, the girder is still never laid over
    -- a worm; the shot is spent then.
    local speed=math.sqrt(vx*vx+vy*vy)
    local dx,dy=0,-1
    if speed>0 then dx,dy=vx/speed,vy/speed end
    if trapped(ev.x,ev.y,dx,dy,flight and flight.shooter) then
      for _,worm in ipairs(wa.worms.all()) do
        if worm.turn then deny(worm); break end
      end
      return
    end
    wa.land.stamp{sprite="sprites/girder_launcher/mgirder.png",frame=orientation(vx,vy),x=ev.x,y=ev.y}
    for _,worm in ipairs(wa.worms.all()) do
      if worm.turn then wa.sound.play(worm,"sounds/girder_launcher/mgirder_impact.wav"); break end
    end
  end
  wa.on.draw(function()
    for _,worm in ipairs(wa.worms.all()) do
      if worm.turn and worm.hp>0 and worm.aiming and worm.weapon=="px.girder_launcher" then
        local angle=(1-worm.aim)*math.pi
        if worm.facing<0 then angle=2*math.pi-angle end
        local dx,dy=math.sin(angle),-math.cos(angle)
        local x,y=worm.x+12*dx,worm.y+12*dy
        local x1,y1=x+15000*dx,y+15000*dy
        local hit=wa.world.trace{x0=x,y0=y,x1=x1,y1=y1,radius=1,with={"terrain"}}
        if hit then x1,y1=hit.x,hit.y end
        wa.draw.ribbon{sprite="sprites/girder_launcher/laser.png",visibility=worm,
          blend="add",depth=wa.depth.FRONT,points={
            {x=x,y=y,width=2,u=0,color=0xC0FF6060},
            {x=x1,y=y1,width=1,u=1,color=0xFFFF3030},
          }}
      end
    end
  end)
end
return weapon
