-- Before any bind is built: the registry wraps hl.bind so every handle is
-- filed under the tree it belongs to. There is no API to enumerate binds
-- afterwards, so this is the only moment they can be grouped at all.
require("hypr.hyprfocus.binds").capture()

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
