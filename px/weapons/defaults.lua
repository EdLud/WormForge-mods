-- Highlander's weapons' data, by id, before a profile's settings: what each
-- weapon needs that its record (built on its home's) doesn't say. A
-- weapon's slot past WA's 70 gives it nothing WA ties to an id, so what it
-- had from its home's id is said here.
return {
  -- PX's Hot Air Balloon and Hang-Glider don't let the worm drill: the
  -- drill's record would, from WA's parachute.
  ["px.super_drill"] = { mid_air = false },
  -- WA places its girders only for ids 34 and 36: the cursor shows the
  -- girder, a click places one where WA allows.
  ["px.3_girder_pack"] = { placement = "girder_pack" },
  -- PX's record gives the Super Tele the scheme's retreat; on WA's
  -- Teleport id the turn ended at once, as WA's own Teleport's does.
  ["px.super_tele"] = { after_use = "end" },
}
