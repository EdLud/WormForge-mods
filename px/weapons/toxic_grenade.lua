-- The source's expanding, terrain-deflected toxic puffs carry native poison.
-- Their movement/exposure is simulation state; drawing cannot change it.
local holds = require("wf-lib/holds")
local weapon = {}
local clouds = {}
local ART = "sprites/toxic_grenade/"
local FINISH_TURN = 55 -- PX M_TURNEND; WA also sends it to a worm during Tab.
local pending_end

local function finish_candidate(worms,confirmed)
  local ending=pending_end
  pending_end=nil
  if not ending then return end
  if not confirmed then
    for _,w in ipairs(worms) do if w.turn then return end end
  end
  for _,s in ipairs(ending) do s.turns=s.turns-1 end
end
local looks = setmetatable({}, {__mode="k"})

local function random_signed()
  return wa.random(-10000,10000)/10000
end

local function puff(x,y)
  return {x=x,y=y,age=0,life=240+40*random_signed(),
    vx=3*random_signed(),vy=3*random_signed()}
end

local function move(p,worms)
  p.age=p.age+1
  -- Source redirects a blocked endpoint by 90 degrees, damping both axes.
  -- Each attempt shrinks speed; bound it as well for buried spawn points.
  for _=1,128 do
    if not wa.land.solid(p.x+p.vx,p.y+p.vy) then break end
    if wa.random(0,1)==0 then
      p.vx=p.vy*-0.94;p.vy=p.vx*0.94
    else
      p.vx=p.vy*0.94;p.vy=p.vx*-0.94
    end
    if math.abs(p.vx)<0.1 and math.abs(p.vy)<0.1 then break end
  end
  if p.age%8==0 then
    for _,w in ipairs(worms) do
      if w.hp>0 and math.abs(w.x-p.x)<20 and math.abs(w.y-p.y)<20 then
        w:poison(2)
      end
    end
  end
  p.x,p.y=p.x+p.vx,p.y+p.vy
  p.vx=p.vx*0.995+0.05*random_signed()
  p.vy=(p.vy-0.02)*0.995+0.05*random_signed()
end

local function detonate(event)
  -- A delayed grenade may outlive its thrower. Choose a current live body,
  -- rather than passing a stale owner to the native actor constructor.
  local owner
  for _,w in ipairs(wa.worms.all()) do
    owner=owner or w
    if event.worm and w.id==event.worm.id then owner=w;break end
  end
  if not owner then return end
  local s={x=event.x,y=event.y,age=0,turns=4,puffs={}}
  local function step(a)
    local worms=wa.worms.all()
    finish_candidate(worms,false)
    -- Existing particles get their frame before the emitter creates new ones.
    local i=1
    while i<=#s.puffs do
      local p=s.puffs[i]
      move(p,worms)
      if p.age>p.life then table.remove(s.puffs,i) else i=i+1 end
    end
    if s.turns>=0 then
      if s.age%8==0 then
        for _=1,6 do s.puffs[#s.puffs+1]=puff(s.x,s.y) end
      end
      s.age=s.age+1
    elseif #s.puffs==0 then
      for i,c in ipairs(clouds) do if c==s then table.remove(clouds,i);break end end
      a:despawn()
    end
  end
  -- One non-colliding driver per cloud; particles do not consume WA body slots.
  s.actor=wa.actors.spawn{sprite=false,owner=owner,x=s.x,y=s.y,gravity=false,collide=false,
    persist=true,drown=false,light=false,on=step}
  clouds[#clouds+1]=s
end

weapon.definition = {
  copy_from="stock.grenade",name="Toxic Grenade",
  panel_icon=ART.."img_toxicgren.png",sprite="grenade",
  handling={remember_selection=false},
  -- ExplodeAt is replaced by the emitter: no native blast, crater or clusters.
  missile={explosion={power=0,push_pct=0},burst="nothing"},on_explode=detonate,
  worm_sprites=holds.PX_POSTURE,
  sprites={ART.."poisongren.png",ART.."smoke.png"},params={gpu_prefix=ART},
  hold={sheet=ART.."poisongren.png",frames=1,hand_radius=18,hand_rotation=1,
    hand_radial_rotation=1.05,weap_radial_rotation=0.9,weap_rotation=0.5,
    weap_radius=10,hand_type=1,hand_scale=0.8,thrown=true},
}
weapon.missile_sprite={sheet=ART.."poisongren.png",frames=1,hide=true}

function weapon.setup()
  wa.on.worm_message(function(_,msg)
    if msg==wa.msg.TURN_STARTED then
      -- A real next team turn can start before a cloud's next frame.
      finish_candidate({},true)
    elseif not pending_end then
      -- Defer until Tab has completed. Another selected worm means this was
      -- only a switch. Snapshot existing clouds, so later throws don't age.
      pending_end={}
      for _,s in ipairs(clouds) do pending_end[#pending_end+1]=s end
    end
  end,{msgs={FINISH_TURN,wa.msg.TURN_STARTED}})
  wa.on.draw(function()
    for _,s in ipairs(clouds) do
      if s.actor.id~=0 then
        for _,p in ipairs(s.puffs) do
          local v=looks[p]
          if not v then
            v={rotation=wa.draw.random()*6,size=0.75+0.1*(wa.draw.random()*2-1)}
            looks[p]=v
          end
          local t=math.min(1,p.age/p.life)
          local half=16*(v.size+(1.75-v.size)*t)
          local angle=v.rotation+p.age*0.05
          local c,sn=math.cos(angle)*half,math.sin(angle)*half
          local alpha=math.floor(255+(35-255)*t)
          wa.draw.quad{sprite=ART.."smoke.png",frame=0,
            color=alpha*0x1000000+0x80DC80,depth=wa.depth.OBJECTS,
            points={{p.x-c+sn,p.y-sn-c},{p.x+c+sn,p.y+sn-c},
              {p.x+c-sn,p.y+sn+c},{p.x-c-sn,p.y-sn+c}}}
        end
      end
    end
  end)
end
return weapon
