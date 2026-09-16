-- The fallback host: a machine with no file of its own in this directory. It
-- is a complete desk on its own — named workspaces on one pair of monitors,
-- no scenes, nothing bespoke — so a new machine boots with something sane
-- instead of an error.
--
-- Spec terms conf/host.lua fills so a host file never repeats them: `layout`
-- ("scene"), `persistent`, and `monitor` ("primary") for plain workspaces. A
-- file spells a field only to deviate: an engine block, a non-primary
-- monitor, a non-default layout.
--
-- This is also the model for a real host file: data first, comments only
-- where a number would otherwise justify itself.
--
-- Special workspaces are retired (LEO-265/330): every scene is now an
-- ordinary workspace admitted per mode. The fallback carries all named
-- workspaces so any mode can resolve; monitors are not pinned (the default
-- machine has no secondary to pin to).
-- Hosts shape (hypr/types.lua); workspace_specs entries are HL.WorkspaceRuleSpec.
---@type Hosts
return {
  primary_monitor = "eDP-1",
  secondary_monitor = "HDMI-A-1",
  hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock.conf",
  workspaces = {
    workspace_specs = {
      { workspace = "1", default = true, default_name = "code" },
      { workspace = "3", default_name = "proton" },
      { workspace = "4", default_name = "dofus" },
      { workspace = "5", default_name = "pokemon" },
      { workspace = "6", default_name = "steam-games" },
      { workspace = "8", default_name = "obsidian-linear" },
      { workspace = "11", default_name = "media", monitor = "secondary" },
      { workspace = "12", default_name = "logs", monitor = "secondary" },
    },
    workspace_keys = {
      "plus",
      "bracketleft",
      "braceleft",
      "parenleft",
      "ampersand",
      "equal",
      "parenright",
      "braceright",
      "bracketright",
      "asterisk",
    },
  },
}
