-- Weapon hints and notices: the shared tooltip window (wf-lib/tooltip).
-- `register(id, reader)` is its `hint`.
local tooltip = require("wf-lib/tooltip")
return { register = tooltip.hint, hint = tooltip.hint, notice = tooltip.notice }
