-- Highlander's weapons' data, by id, before a profile's settings: what each
-- weapon needs that its record (built on its home's) doesn't say. A
-- weapon's slot past WA's 70 gives it nothing WA ties to an id, so what it
-- had from its home's id is said here.
return {
  -- PX's Hot Air Balloon and Hang-Glider don't let the worm drill: the
  -- drill's record would, from WA's parachute.
  ["px.super_drill"] = { mid_air = false },
}
