-- Run from this bundle: lua test_weapon.lua
local claim, keys, in_hud = nil, {}, false
local actors, fields, lines = {}, {}, {}
local hooks = {turn_start={},turn_end={},hud={}}
wa = {
  weapons = {replace=function(s) claim=s end},
  cursor = {spawn=function(s)
    local a = {spec=s,dead=false}
    function a:despawn() self.dead=true end
    actors[#actors+1]=a
    return a
  end},
  magnetism = {field=function(s)
    local data={}
    for k,v in pairs(s) do data[k]=v end
    local f=setmetatable({}, {
      __index=data,
      __newindex=function(_,k,v)
        assert(not in_hud,'HUD must not write a magnetic field')
        assert(not data.removed,'write through a removed field')
        data[k]=v
      end,
    })
    function data.remove()
      assert(not in_hud and not data.removed)
      data.removed=true
    end
    fields[#fields+1]=f
    return f
  end},
  world = {
    pointer=function() return {x=400,y=200} end,
    keys=function() assert(not in_hud,'read simulation keys in the simulation'); return keys end,
  },
  hud={line=function(text) lines[#lines+1]=text end},
  on={},
}
for name,handlers in pairs(hooks) do
  wa.on[name]=function(fn) handlers[#handlers+1]=fn end
end
local function emit(name,ev)
  for _,fn in ipairs(hooks[name]) do fn(ev) end
end
local component=dofile('weapon.lua')
assert(component.defaults.ammo.round_start==-1)
component.install{id='magnets.magnet_cursor'}
assert(claim.copy_from=='stock.teleport' and claim.fires.aims)
assert(claim.on_select.cursor and claim.eat_fire and claim.click_finish==false)
assert(claim.handling.ends_turn==false)
local worm={id=1,turn=true,hp=100,weapon='magnets.magnet_cursor'}
local function select() claim.on_select.on{worm=worm,x=120,y=80} end
select()
local a,f=actors[#actors],fields[#fields]
assert(a.spec.owner==worm and a.spec.x==120 and a.spec.y==80)
assert(f.source==a and f.range==300 and f.strength==14000 and f.max_force==12)
assert(f.polarity=='attract' and f.softening==10)
for digit=1,9 do
  keys.digit=digit
  a.spec.on()
  assert(f.strength==14000*digit and f.max_force==12*digit and f.range==300)
end
keys.digit=0; a.spec.on()
assert(f.strength==126000,'0 does not reset or disable the field')
keys.digit=nil
keys.plus_key=true
for _=1,5 do a.spec.on() end
assert(f.polarity=='repel' and f.softening==5,'held + toggles once')
keys.plus_key=false; a.spec.on()
keys.plus_key=true; a.spec.on()
assert(f.polarity=='attract' and f.softening==10,'a new press toggles again')
keys.digit=2
in_hud=true; emit('hud'); in_hud=false
assert(lines[#lines]:find('9x') and lines[#lines]:find('ATTRACT'),'HUD shows the applied state')
keys.digit=nil
claim.on_click{}
assert(not a.dead and not f.removed and #actors==1,'click consumes no shot or cursor')
select()
assert(a.dead and f.removed,'reselect removes the previous field and source')
a,f=actors[#actors],fields[#fields]
assert(f.strength==126000 and f.polarity=='attract','settings persist without toggling a held +')
worm.weapon='stock.skip_go'; a.spec.on()
assert(a.dead and f.removed,'weapon switch removes the field')
local count=#actors
emit('hud')
assert(#lines==1,'inactive cursor has no HUD line')
emit('turn_start',{worm=worm})
assert(#actors==count,'another selected weapon creates no field')
worm.weapon='magnets.magnet_cursor'
emit('turn_start',{worm=worm})
a,f=actors[#actors],fields[#fields]
assert(a.spec.x==400 and a.spec.y==200,'turn restoration starts at the synchronized pointer')
assert(f.strength==126000)
emit('turn_end',{worm=worm}); emit('turn_end',{worm=worm})
assert(a.dead and f.removed,'turn-end cleanup is idempotent')
emit('turn_start',{worm=worm})
a,f=actors[#actors],fields[#fields]
worm.hp=0; a.spec.on()
assert(a.dead and f.removed,'death removes source and field')
count=#actors
worm.hp,worm.turn=100,false
select()
assert(#actors==count,'inactive selection creates no field')
print('PASS: strength 1-9, polarity edges, HUD reads, click/reselect, weapon switch, turns, death and inactive selection')
