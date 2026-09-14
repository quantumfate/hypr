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

-- The which-key tree only changes with a config reload, so dump it once now
-- (boot or reload) and let the shell's FileView watch pick it up.
require("hypr.lib.whichkey").dump()
