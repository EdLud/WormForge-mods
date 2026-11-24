The turret sits in the Dynamite slot: Space plants a persistent Lua actor the way a mine is placed.

Line of sight is `wa.land.trace`. A round is `worm:hit` plus a shove along the bore, not a stock blast. It only tracks worms that moved last tick. With an empty clip it keeps sweeping, and it refills when the planter’s turn starts.

Each team colour × idle/firing pose is one 120-frame GIF (`a:frame` is the 360° aim). Needs no other dynamite overlay.
