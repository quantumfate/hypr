local window_rule = require("hypr.lib.window_rule")
local conf = require("hypr.windowrules.conf")

window_rule.apply_scopes(conf.tag_scopes)
window_rule.apply_workspace_assigns(conf.workspace_assigns)
window_rule.apply_rules(conf.rules)
window_rule.apply_named(conf.named)
