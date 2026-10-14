# cut_lab

A test bench for `wa.land.cut`. The Bazooka (named Cut Lab) cuts a hole of the
chosen shape where it lands; its own blast is reduced to almost nothing.

- **+** cycles the shape: circle, drill, torch, star, ring.
- **1-9, 0** set the size: a circle's radius (8 to 80 pixels), or the star's
  and ring's frame (12 to 120 pixels across). The drill and torch are WA's own
  and have one size.

The star and ring are `shape = "sprite"` cuts from `sprites/star` and
`sprites/ring`. The ring's middle is left solid, so it shows the mask cutting
around a hole. The HUD names the current shape and size.

A WF scheme that places its own weapon in the Bazooka slot (Highlander's has
Double Bazooka) wins the slot, so test with no WF scheme chosen.
