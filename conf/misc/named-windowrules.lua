-- Named window rules (ported from conf/misc/named-windowrules.conf).
-- Named rules can be toggled at runtime and are evaluated before anonymous ones.

hl.window_rule({
  name    = "opaque-media-browser",
  enabled = false,
  match   = { tag = "media-browser" },
  opacity = "1 override",
})

hl.window_rule({
  name    = "opaque-default-browser",
  enabled = false,
  match   = { tag = "default-browser" },
  opacity = "1 override",
})

hl.window_rule({
  name      = "feh",
  match     = { initial_class = "feh" },
  workspace = "special:feh",
  float     = true,
  content   = "photo",
  center    = true,
  rounding  = 0,
  opacity   = "1 override 1 override",
})

hl.window_rule({
  name      = "workspace-spotify",
  match     = { initial_class = "([Ss]potify)" },
  workspace = "special:spotify",
})

hl.window_rule({
  name      = "workspace-vesktop",
  match     = { initial_class = "vesktop" },
  workspace = "special:vesktop",
})
