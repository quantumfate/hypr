-- Special workspaces (ported from conf/workspaces.conf).
-- The originals used workspace selectors `s[true]n[e:NAME]` (special workspace
-- whose name ends with NAME); the only actionable rule was on-created-empty.

hl.workspace_rule({ workspace = "special:spotify", on_created_empty = "spotify" })
hl.workspace_rule({ workspace = "special:vesktop", on_created_empty = "vesktop" })

-- NOTE: the original "feh" line (`workspace=s[true]n[e:feh], name:feh`) carried
-- no valid workspace rule (`name:feh` is not a rule), so there is nothing to
-- port. feh window placement is handled by the "feh" named window rule in
-- conf/misc/named-windowrules.lua.
