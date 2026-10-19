# Cursor Light

Requires the actor-light DLL and the **Fog of war** add-on (`core.fog`).
Load the supplied **Cursor Light** profile, select **Cursor Light** with F8,
and move the mouse. The land cursor emits a 300 px circle of white light;
terrain blocks it, leaving darkness behind hills and walls. HUD and chat stay
visible. A cursor inside solid terrain has the cast that position allows.

Clicking uses no ammo and keeps the cursor active. Switching weapons, death,
or the end of the turn removes the cursor and light. Skip Go (F12) is included
to test turn changes. When Cursor Light stays selected, the next turn restores
its cursor. Terrain memory is off, so moving the cursor leaves no explored trail.
The light follows its owning worm's vision side, according to the fog profile.

This is Lua only: `wa.cursor.spawn` supplies WA's existing cursor movement and
`a.light` explicitly enables terrain-blocked light on the cursor actor. The
weapon does not change global fog settings; other profiles can place it too.
