require("hypr.conf")
require("hypr.workspaces")
require("hypr.events")
require("hypr.layouts")
require("hypr.services")
require("hypr.themes")

require("hypr.animations")
require("hypr.binds")
require("hypr.layerrules")
require("hypr.monitors")
require("hypr.lib.diagnose").attach()
require("hypr.windowrules")

-- The which-key document must answer from the enabled set, not the full
-- registry (LEO-324). Boot (or reload) applies the mode the pointer already
-- names; that path re-dumps the cheatsheet from the loaded trees before the
-- shell's FileView reads it. If no declaration exists yet, fall back to the
-- unfiltered dump so the file is at least present.
local hyprfocus = require("hypr.hyprfocus")
local ok, report = pcall(hyprfocus.apply, hyprfocus.active())
if not ok or not report then
  require("hypr.lib.whichkey").dump()
end
