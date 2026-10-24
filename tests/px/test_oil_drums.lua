-- Project X's oil drums (lib/oil_drums.lua) against a mocked WA: the deal,
-- what each kind bursts into, and how it is drawn.
--
--   lua mods/tests/px/test_oil_drums.lua        (from the engine repo root)
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local M
local function mock(opts)
  opts = opts or {}
  M = { drums = {}, worms = {}, actors = {}, fires = {}, mines = {}, launches = {}, sounds = {},
    quads = {}, randoms = {}, frame = 0, cavern = opts.cavern or false,
    rng = function(lo) return lo end }
  local function worm(id, team, x, y, hp)
    local w = { id = id, team = team, x = x, y = y, hp = hp or 100 }
    function w:freeze() M.frozen = M.frozen or {}; M.frozen[#M.frozen + 1] = self.id; return true end
    M.worms[#M.worms + 1] = w
    return w
  end
  M.worm = worm
  M.drum = function(uid, x, y)
    local d = { uid = uid, id = uid, kind = "oil", x = x, y = y, damage = 0, max_damage = 50, visible = true }
    M.drums[#M.drums + 1] = d
    return d
  end
  package.loaded["lib/shared"] = {
    current_worm = function() return M.turn end,
    nuke_rocket_first = function(...) M.rockets = M.rockets or {}; M.rockets[#M.rockets + 1] = { ... } end,
    electric_grenade_explode = function(ev) M.arc = ev end,
    swim_suit_off = function(w) M.unsuited = M.unsuited or {}; M.unsuited[#M.unsuited + 1] = w.id end,
  }
  package.loaded["lib/oil_drums"] = nil
  wa = {
    log = function() end,
    msg = { FRAME_FINISH = 2 },
    math = { sin = math.sin, cos = math.cos },
    random = function(lo, hi) M.randoms[#M.randoms + 1] = { lo, hi }; return M.rng(lo, hi) end,
    world = { cavern = function() return M.cavern end, frame = function() return M.frame end },
    oil = { all = function()
      local out = {}
      for _, d in ipairs(M.drums) do out[#out + 1] = d end
      return out
    end },
    worms = { all = function() return M.worms end },
    actors = { spawn = function(spec)
      local a = { id = #M.actors + 1, spec = spec }
      function a:despawn() self.dead = true end
      M.actors[#M.actors + 1] = a
      return a
    end },
    fire = { spawn = function(spec) M.fires[#M.fires + 1] = spec end },
    mines = { spawn = function(spec) M.mines[#M.mines + 1] = spec end },
    weapons = { launch = function(spec) M.launches[#M.launches + 1] = spec; return 1 end },
    sound = { play = function(target, s) M.sounds[#M.sounds + 1] = { target, s } end },
    draw = { quad = function(q) M.quads[#M.quads + 1] = q end },
    on = {
      worm_message = function(f) M.tick = f end,
      oil_explode = function(f) M.explode = f end,
      draw = function(f) M.draw = f end,
    },
  }
  require("lib/oil_drums").install({ nuke = opts.nuke ~= false })
end

local function frame()
  M.frame = M.frame + 1
  M.tick()
end

-- The drum `d` goes off, set off by `team`; true when the pack replaced WA's blast.
local function burst(d, team)
  local ev = { drum = d, x = d.x, y = d.y, team = team or 0 }
  function ev:replace() self.replaced = true end
  M.explode(ev)
  return ev.replaced
end

-- One drum of `kind` (by its place in PX's deal) at (500, 300).
local DEAL = { explosive = 1, napalm = 2, nuke = 3, cluster = 4, icy = 5, electric = 6, mine = 7, teleport = 8 }
local function drum_of(kind, opts)
  mock(opts)
  M.rng = function() return DEAL[kind] end
  M.turn = M.worm(16, 1, 400, 300)
  local d = M.drum(1, 500, 300)
  frame()
  return d
end

local function blasts()
  local out = {}
  for _, a in ipairs(M.actors) do
    if a.spec.explode then out[#out + 1] = a.spec.explode end
  end
  return out
end

print("oil drums: the deal")
do
  mock({ nuke = false })
  local seen = {}
  M.rng = function(lo, hi) seen[#seen + 1] = hi; return lo end
  local c, a, b = M.drum(3, 0, 0), M.drum(1, 10, 0), M.drum(2, 20, 0)
  frame()
  check("every drum dealt once, in uid order: kinds drawn for 1, 2, 3",
    #M.randoms == 3 and M.randoms[1][1] == 1)
  check("without the Nuke Rocket: six kinds on an open map", seen[1] == 6, seen[1])
  check("WA stops drawing each", not a.visible and not b.visible and not c.visible)
  frame()
  check("a drum is dealt once", #M.randoms == 3)
  mock({ cavern = true })
  M.drum(1, 0, 0)
  local hi
  M.rng = function(lo, h) hi = h; return h end
  frame()
  check("on a cavern map the teleport drum joins the deal", hi == 8, hi)
end

print("oil drums: what each kind bursts into")
do
  local d = drum_of("explosive")
  check("the pack stands in for WA's blast", burst(d) == true)
  local f = M.fires
  check("explosive: three of PX's fires, 18 flames 6.3 s, 17 damage",
    #f == 3 and f[1].count == 18 and f[1].duration == 6300 and f[1].damage == 17 and f[1].up_power == 100
    and f[1].vx == -3 and f[1].vy == -3 and f[1].y == 299 and f[2].vx == 3 and f[2].y == 301
    and f[3].vx == 0 and f[3].vy == -8 and f[3].y == 298)
  local b = blasts()
  check("explosive: PX's blast, kind 100, damage 85", #b == 1 and b[1].id == 100 and b[1].damage == 85 and b[1].now)

  drum_of("napalm")
  burst(M.drums[1])
  check("napalm: seven fires of 25 flames, 8.3 s, and a 25 blast",
    #M.fires == 7 and M.fires[1].count == 25 and M.fires[1].duration == 8300 and blasts()[1].damage == 25)

  drum_of("nuke")
  M.rng = function(lo) return lo end
  burst(M.drums[1])
  local r = M.rockets or {}
  check("nuke: a kind-80 blast of 20", blasts()[1].id == 80 and blasts()[1].damage == 20)
  check("nuke: two of the Nuke Rocket's rockets, PX's speeds", #r == 2
    and r[1][2] == 500 and r[1][4] == -1.1 and r[1][5] == -0.5 and r[2][4] == -2.5 and r[2][5] == -2.4)

  drum_of("cluster")
  burst(M.drums[1])
  local l = M.launches[1]
  check("cluster: the Cluster Bomb's bursting at once into its clustlets", l
    and l.weapon == "stock.cluster_bomb" and l.missile.fuse == 0 and l.missile.burst == "clusters"
    and l.missile.explosion.power == 20 and blasts()[1].damage == 10)

  drum_of("icy")
  local near = M.worm(2, 2, 600, 300)
  M.worm(3, 2, 700, 300)
  M.worm(4, 2, 520, 300, 0)
  burst(M.drums[1])
  table.remove(M.drums, 1) -- WA frees the drum after it goes off
  check("icy: living worms within 150 pixels frozen, suits off", M.frozen and #M.frozen == 2
    and M.frozen[1] == near.id and M.frozen[2] == 16 and #M.unsuited == 2, M.frozen and table.concat(M.frozen, ","))
  check("icy: PX's sound 24", M.sounds[1] and M.sounds[1][2] == 24)
  M.quads = {}
  M.draw()
  local adds = 0
  for _, q in ipairs(M.quads) do if q.blend == "add" then adds = adds + 1 end end
  check("icy: 400 blue specks drawn", adds == 400, adds)
  for _ = 1, 70 do frame() end
  M.quads = {}
  M.draw()
  check("icy: gone after 70 frames", #M.quads == 0, #M.quads)

  drum_of("electric")
  burst(M.drums[1])
  check("electric: the Electric Grenade's arc for 30 frames, the turn's worm spared",
    M.arc and M.arc.life == 30 and M.arc.worm == M.turn and M.arc.x == 500 and blasts()[1].damage == 10)

  drum_of("mine")
  M.rng = function(lo) return lo end
  burst(M.drums[1])
  local m = M.mines
  check("mine: seven of WA's mines, PX's 3 s arming and fuse, 48 damage and radius", #m == 7
    and m[1].arm == 3000 and m[1].fuse == 3000 and m[1].damage == 48 and m[1].radius == 48
    and m[1].vx == -7 and m[1].vy == -7)
  check("mine: laid by an actor, for no team", m[1].owner == M.actors[1] and M.actors[1].spec.explode == nil)

  drum_of("teleport", { cavern = true })
  burst(M.drums[1])
  check("teleport: the turn's worm to the drum, PX's two sounds",
    M.turn.x == 500 and M.turn.y == 294 and M.sounds[1][2] == 68 and M.sounds[2][2] == 67)

  drum_of("explosive")
  M.worm(5, 2, 0, 0)
  M.worm(3, 2, 0, 0)
  burst(M.drums[1], 2)
  check("the team that set it off owns the blast: its first worm",
    M.actors[1].spec.owner.id == 3, M.actors[1].spec.owner.id)
end

print("oil drums: drawing")
do
  local d = drum_of("explosive")
  d.damage = 30
  M.quads = {}
  M.draw()
  local body, extra = M.quads[2], M.quads[1]
  check("the drum dented as WA's, scaled as PX's", body and body.sprite == "sprites/oil_drums/explosive3.png"
    and body.depth == 16 * 0x10000 and (body.points[2][1] - body.points[1][1]) == 90 * 1.2, body and body.sprite)
  check("its extra in front, at PX's opacity", extra and extra.sprite == "sprites/oil_drums/explosive_fallout.png"
    and extra.depth == 14 * 0x10000 and (extra.color >> 24) == 160)
end

print("oil drums: every sheet drawn is loaded")
do
  -- A quad naming a sheet the add-on never loaded errors in the engine,
  -- and the rest of that frame's draw, every drum, is lost with it.
  local loaded = {}
  for _, s in ipairs(require("lib/oil_drums").sprites()) do loaded[s] = true end
  local missing = {}
  for kind in pairs(DEAL) do
    local d = drum_of(kind, { cavern = true })
    for dent = 0, 50, 15 do
      d.damage = dent
      M.quads = {}
      M.draw()
      for _, q in ipairs(M.quads) do
        if not loaded[q.sprite] then missing[q.sprite] = true end
      end
    end
    burst(d)
    for _ = 1, 3 do frame() end
    M.quads = {}
    M.draw()
    for _, q in ipairs(M.quads) do
      if not loaded[q.sprite] then missing[q.sprite] = true end
    end
  end
  local names = {}
  for s in pairs(missing) do names[#names + 1] = s end
  table.sort(names)
  check("drums, extras and bursts draw only loaded sheets", #names == 0, table.concat(names, ", "))
end

if failed > 0 then error(failed .. " FAILED") end
print("Project X's oil drums: the deal, each kind's burst and drawing: ALL PASS")
