-- Highlander, on Project X's weapon layout.
--
-- A port of Project X's `scheme_hl_0rang3` (Highlander 0rang3 1.1). Every
-- worm is dealt one weapon from each of three pools at the start of the match.
-- Only the worm whose turn it is may use its weapons, one shot of each per
-- turn. Kill a worm and you take everything it carried.
--
-- The scheme puts each of its weapons on one of WA's 71 stock slots: the
-- Baseball Bat on the girder's, the Cluster Bomb on the magic bullet's, and
-- so on. The pools below are PX's own lists, in PX's order, each weapon
-- written as the stock slot it takes. A weapon not ported yet leaves WA's
-- stock weapon on its slot, and that stands in for it.
--
-- The source (`highlander.txt`) does all of this with four calls:
-- SetWeaponEx(team, weapon, 1) to grant and SetWeaponEx(team, weapon, 0) to
-- take away. `worm:ammo(name, { set = n })` is the same absolute write. It has
-- to be absolute: a stock scheme gives some of these weapons infinite ammo,
-- and adding to infinite leaves it infinite.
--
-- Where this differs from the source, on purpose:
--
--   * No turn-end removal. PX removes a worm's weapons at M_TURNEND and again,
--     through CurW, at the next M_TURNBEGIN. The second alone is enough, so
--     this listens for one message instead of two.
--
--     START_TURN (0x34) reaches only the worm whose turn it is: WA's handler
--     marks the receiver turn-active and calls TeamArena::SetActiveWorm on it
--     unconditionally (OpenWA `msg_start_turn`), which would be nonsense sent
--     to every worm. So the worm it arrives on IS the active worm.
--
--   * Every pooled slot is zeroed for every team at each turn start, not
--     just the previous worm's. PX relied on its scheme having those slots at
--     zero. Here the scheme can say anything, so the pack enforces it itself.
--
--   * PX's GiveWeapons also sets the Hot Air Balloon to 3 and the Wind
--     Changer to 1 each turn; so does start_turn.
--
-- Lockstep: dealing, turn_start and death are all dispatched from WA's own
-- simulation messages, and every random choice is wa.random(). Two peers, or
-- a peer and a replay, deal the same hands and make the same grants. Nothing
-- here reads local input or the clock.

-- The pack's code is split into modules, run in this order; together
-- they are the pack. tools/split_highlander.py made them from the
-- single rules.lua this file once was.
require("lib/holds")
require("weapons/catalog")
require("weapons/wep_data")
require("weapons/claims")
require("weapons/super_drill")
require("weapons/fire_jump")
require("lib/anim")
require("weapons/sniper_rifle")
require("lib/missile_sprites")
require("weapons/double_bazooka")
require("weapons/chilli_bomb")
require("weapons/nuke_rocket")
require("weapons/helicopter")
require("weapons/hot_air_balloon")
require("weapons/hang_glider")
require("weapons/swim_suit")
require("weapons/wind_gravity")
require("weapons/jump")
require("weapons/laser_gun")
require("scheme/pools")
require("scheme/state")
require("scheme/rules")
require("weapons/super_tele")
require("weapons/electrical")
require("weapons/javelin")
require("weapons/ice_arrow")
require("weapons/valyrian_fire")
require("weapons/reinforcement")
