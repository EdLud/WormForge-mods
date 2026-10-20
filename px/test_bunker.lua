-- Movement regressions for both Bunker Busters. The engine field calculation
-- and opt-in contract are tested through real bindings in lua-host.
local root = HIGHLANDER_ROOT or "mods/px/"
local bunker = assert(loadfile(root .. "lib/px_bunker.lua"))()
local actors, claim, fx, fy, inside, terrain, blasts, cuts, flames, probes
local function reset(super, force_x, force_y, active)
  actors, blasts, cuts, flames, probes = {}, {}, {}, {}, {}
  fx, fy, inside, terrain = force_x or 0, force_y or 0, active or false, false
  wa = {
    log = function() end,
    depth = { OBJECTS = 20 },
    math = { atan = math.atan },
    sound = { play = function() end },
    random = function(a) return a end,
    magnetism = { sample = function() return fx, fy, inside end },
    world = {
      gravity = function() return 0.25 end, water = function() return 10000 end,
      cavern = function() return false end, trace = function() return nil end,
    },
    land = {
      trace = function(x0,y0,x1,y1)
        probes[#probes+1] = {x0,y0,x1,y1}
        if terrain then return {x=x1,y=y1} end
      end,
      solid = function() return terrain end,
      cut = function(s) cuts[#cuts+1] = s end,
    },
    fire = { spawn = function(s) flames[#flames+1] = s end },
    weapons = { replace = function(s) claim = s end },
    actors = { spawn = function(s)
      local a = { x=s.x,y=s.y,vx=s.vx or 0,vy=s.vy or 0,id=#actors+1,on=s.on,sprite=s.sprite }
      function a:despawn() self.dead = true end
      function a:scale(v) self.scale_value = v end
      function a:explode(s) blasts[#blasts+1] = {x=self.x,y=self.y,spec=s} end
      function a:look(s) self.sprite = s end
      function a:frame() end
      function a:sound() end
      function a:gfx(s) self.gfx_spec = s end
      actors[#actors+1] = a
      return a
    end },
  }
  bunker.install({id=super and "px.super_bunker_buster" or "px.bunker_buster"})
  claim.on_click({worm={id=1},x=100,y=0})
  return actors[1]
end
local function frames(a,n) for _=1,n do if not a.dead then a.on(a) end end end
local function near(a,b) assert(math.abs(a-b)<1e-9, tostring(a).." ~= "..tostring(b)) end

for _,super in ipairs({false,true}) do
  local a=reset(super)
  frames(a,10)
  near(a.x,100); near(a.y,-128+0.25*55)
  near(a.gfx_spec.angle,0)
  a=reset(super,1,0,true)
  frames(a,1)
  near(a.x,100.4); near(a.y,-127.75)
  assert(a.gfx_spec.angle<0,"falling art follows the magnetic deflection")

  a=reset(super)
  terrain=true
  frames(a,1) -- enter the ground vertically
  local start_x,start_y=a.x,a.y
  fx,fy,inside=1000,0,true
  frames(a,1)
  local dx,dy=a.x-start_x,a.y-start_y
  local length=math.sqrt(dx*dx+dy*dy)
  near(length,1.15)
  near(dx/length,0.3/math.sqrt(100+0.09)) -- PX's 0.1 force cap and 10:3 blend
  assert(a.gfx_spec.angle<0,"drilling art rotates with its direction")
  assert(probes[#probes][3]~=probes[#probes][1],"terrain probes follow the angled drill")
  if super then
    assert(#flames>0 and flames[1].x<a.x,"super's fire comes from behind the steered drill")
    near(actors[2].gfx_spec.angle,a.gfx_spec.angle)
  end

  -- Losing the field preserves the steered direction; it does not reset
  -- the drilling clock or change the drill's fixed speed.
  fx,fy,inside=0,0,false
  local px,py=a.x,a.y
  frames(a,1)
  near(a.x-px,dx); near(a.y-py,dy)
  frames(a,super and 448 or 298)
  assert(a.scale_value==0,"the original drilling budget still expires")
  frames(a,50)
  assert(a.dead,"the blast sequence completes")
  assert(#blasts==(super and 9 or 1))
  if super then
    local x1,y1=blasts[2].x-blasts[1].x,blasts[2].y-blasts[1].y
    near(x1*dx+y1*dy,0)
    near(math.sqrt(x1*x1+y1*y1),40)
  end

  -- Leaving land retains a sideways velocity, then resumes ordinary fall.
  a=reset(super)
  terrain=true; frames(a,1)
  fx,fy,inside=2,0,true; frames(a,10)
  terrain=false; fx,fy,inside=0,0,false
  frames(a,1)
  local old_x=a.x
  frames(a,1)
  assert(a.x>old_x,"a steered drill carries momentum out of the terrain")
end
print("Bunker Busters: magnetic fall, capped steering, rotated probes/art/flare, original lifetime: ALL PASS")
