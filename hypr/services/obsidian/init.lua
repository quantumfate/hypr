-- Obsidian vault: the new-note form and store queries. The UI owns the
-- interaction (quickshell modules/obsidian/ObsidianCreate.qml + the
-- ObsidianVault service); keybinds just push IPC — same shape as the dofus
-- service, minus window guards (a capture hotkey is global, never context-tied).
local qs = require("hypr.lib.qs")
local submap = require("hypr.lib.submap")

submap.tree({
  mods = { config.main_mod, "o" },
  name = "obsidian",
  desc = "Obsidian",
  sticky = false,
  entries = {
    {
      key = "n",
      desc = "New note",
      action = function()
        -- toggle: the same bind opens the form and (while it is up) closes it,
        -- aborting a create that is still running.
        qs.call("obsidianCreate", "toggle")
      end,
    },
    {
      key = "s",
      desc = "Vault status",
      action = function()
        qs.notify("Obsidian", "obsidian", "status")
      end,
    },
    {
      key = "t",
      desc = "Tag tree",
      action = function()
        qs.notify("Obsidian topics", "obsidian", "tree")
      end,
    },
  },
})
