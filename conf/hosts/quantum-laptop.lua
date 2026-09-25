-- quantum-laptop: one internal panel, an external slot. Workspaces live on
-- the primary; the spec defaults (persistent, the scene layout, primary
-- monitor) are filled by conf/host.lua — a file spells a field only to
-- deviate.
--
-- Special workspaces are retired (LEO-265/330): every scene that used to live
-- in `special:*` is now an ordinary workspace admitted per mode. On the
-- laptop, secondary-pinned scenes use HDMI-A-1 when an external monitor is
-- connected; otherwise they fall back to primary.
-- Hosts shape (hypr/types.lua); workspace_specs entries are HL.WorkspaceRuleSpec.
---@type Hosts
return {
  primary_monitor = "eDP-1",
  secondary_monitor = "HDMI-A-1",
  hyprlock_conf = os.getenv("HOME") .. "/.config/hypr/hyprlock-laptop.conf",
  -- Gaps are geometry, resolved by output fingerprint (conf/base.lua's
  -- geometry_profiles), not by which host this is.
  kb_options = "caps:swapescape",
  workspaces = {
    workspace_specs = {
      -- Deck (docs/deck.md): the project column flips through open project
      -- groups, the browser column sits beside it (hyprfocus scene "code").
      { workspace = "1", default = true, default_name = "code", layout = "deck" },
      -- Knowledge and reference, same roles as the desktop: the vault deck on
      -- the main panel, the browser on the secondary (which on a laptop
      -- resolves back to the built-in panel unless one is plugged in).
      { workspace = "2", default_name = "knowledge", layout = "deck" },
      { workspace = "7", default_name = "reference", monitor = "secondary" },
      { workspace = "3", default_name = "proton" },
      -- Dofus: the tile geometry is a fixed capture region, so this scene's
      -- declaration must opt out of solo framing itself (`solo_frame =
      -- false`) — see the matching note on quantum-desktop.lua.
      { workspace = "4", default_name = "dofus" },
      { workspace = "5", default_name = "pokemon" },
      { workspace = "6", default_name = "steam-games" },
      { workspace = "8", default_name = "obsidian-linear", monitor = "secondary" },
      { workspace = "11", default_name = "media", monitor = "secondary" },
      { workspace = "12", default_name = "logs", monitor = "secondary" },
    },
    -- Communication, Lutris, Steam and the Ankama Launcher are shelves now
    -- (conf/base.lua `shelves`), not workspaces.
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
