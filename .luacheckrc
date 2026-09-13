column_width = 120
line_endings = "Unix"
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferDouble"
call_parentheses = "Always"

-- `hl` and `config` are provided by the Hyprland Lua runtime and by
-- hyprland.lua's bootstrap respectively; neither is reassigned by the config.
read_globals = {
  "hl",
  "config",
}

-- Method-style modules (M:foo()) routinely don't touch self; that's the point
-- of the calling convention, not a bug to flag.
self = false

files = {
  ["tests"] = {
    -- Specs deliberately mutate the `hl` stub's fields (stubbing a method per
    -- test) and one spec overrides os.getenv (no os.setenv in stock Lua) to
    -- point store.lua at a scratch dir — both writable here only, unlike the
    -- read-only runtime globals above.
    globals = { "hl", "os" },
  },
}
