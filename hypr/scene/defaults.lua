-- The scenes store's serialized default: what Config seeds into
-- $XDG_STATE_HOME/scenes.json on first run, before any editor has written it.
--
-- This is data, not a host fork: the host files describe a MACHINE (workspace
-- ids, monitor names) and the store is meant to be edited by the user (LEO-239
-- from the shell, or a hand edit) — the default is only what a desk starts
-- with, exactly as a quickshell Store's `defaults` seeds its file. Keyed by
-- workspace `default_name`, never by id: ids are host data.
--
-- The shape here is the engine's raw language (`hypr/scene/spec.lua`
-- normalizes it). It is deliberately richer than the layout_opts-only tuple
-- the host files carried and not yet the full window-scene model
-- (quickshell's scenes schema, LEO-235's members/gaps/layout those documents
-- describe); the editor contract (LEO-239) owns that widening, in one store,
-- so this document and that model converge rather than coexist.
--
-- LEO-330: every focus mode gets a distinct scene layout. Special workspaces
-- are retired — every scene that used to live in `special:*` is now an
-- ordinary workspace admitted per mode.
return {
  -- The seed's own generation. A store carrying an OLDER generation (or none)
  -- is re-seeded once on load — the seed is the shipped default, and a
  -- document it predates cannot hold what it was never written with. User
  -- edits after that are their own, so this is version-keyed and one-way:
  -- a document can only be newer than this file, never older in interest.
  version = 3,
  scenes = {
    -- Gaming scenes (admitted by gaming mode) ---------------------------

    -- Dofus: the primary gaming workspace. A group of Dofus clients fills
    -- the left 67%; a companion browser fills the right 33% for streaming
    -- media and the OBS crop. `collect` pulls drifted clients home because
    -- the group is the scene — a client left behind is one the roster and
    -- the crop both stop seeing. `deny` on the companion prevents it from
    -- joining the Dofus group; it exists as a fixed capture region.
    dofus = {
      blocks = {
        {
          classes = { "Dofus.x64" },
          group = true,
          order = 1,
          share = 0.67,
          collect = true,
          spawn = { class = "zen-gaming-media", command = "zen-twilight -P GamingMedia --name zen-gaming-media" },
        },
        { classes = { "zen-gaming-media" }, order = 2, share = 0.33, guard = "deny" },
      },
      barred = { "steam_app_default", "steam_app_\\d+", "Ankama Launcher" },
      -- Fixed capture region: a stray that takes a slot shifts the split
      -- the OBS crop is aimed at, so unmatched windows float above it.
      strays = "float",
      bindings = {},
      moods = { "gaming" },
    },

    -- Pokemon: emulator window + two streaming media browsers. The
    -- RetroArch window is the active game; the browsers show the chat and
    -- the stream preview. Three-tile split with the emulator in the centre
    -- and media flanking. Unmatched windows float to preserve the streaming
    -- geometry.
    pokemon = {
      blocks = {
        { classes = { "zen-gaming-media" }, order = 1, share = 0.35, guard = "deny" },
        { classes = { "com.libretro.RetroArch" }, order = 2, share = 0.30 },
        { classes = { "zen-gaming-media" }, order = 3, share = 0.35, guard = "deny" },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "gaming" },
    },

    -- Steam games: fullscreen proton/steam windows. One tile, no split —
    -- every game takes the full workspace. Unmatched windows float to avoid
    -- disrupting the fullscreen layout.
    ["steam-games"] = {
      blocks = {
        { classes = { "steam_app", "steam_app_\\d+" }, order = 1, share = 1.0 },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "gaming" },
    },

    -- Communication: Signal and Vesktop side by side. 50/50 split.
    -- Unmatched windows float to preserve the symmetric layout.
    communication = {
      blocks = {
        { classes = { "signal" }, order = 1, share = 0.5 },
        { classes = { "vesktop" }, order = 2, share = 0.5 },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "gaming" },
    },

    -- Lutris: game launcher, fullscreen. Single tile.
    lutris = {
      blocks = {
        { classes = { "net.lutris.Lutris" }, order = 1, share = 1.0 },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "gaming" },
    },

    -- Steam client: the store/library window (not a game). Fullscreen.
    -- The floating "Steam" startup window shares the class; the title
    -- distinguishes them (empty on the startup splash, "Steam" on the
    -- real window).
    steam = {
      blocks = {
        { classes = { "steam" }, order = 1, share = 1.0 },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "gaming" },
    },

    -- Media: fullscreen media player. Admitted by gaming mode for
    -- watching streams or videos beside the gaming workspace.
    media = {
      blocks = {
        { classes = { "mpv", "firefox" }, order = 1, share = 1.0 },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "gaming" },
    },

    -- Work + study scenes (admitted by work/study modes) ----------------

    -- Code: the coding workspace. Terminals form one group on the left 67%;
    -- the browser fills the right 33%. No `collect`: a project terminal
    -- you moved away is where you wanted it. The custom columns layout
    -- (LEO-308/311) is a follow-up; for now this uses the two-tile split.
    code = {
      blocks = {
        { classes = { "Kitty-Main", "Proj-[A-Za-z0-9_-]+" }, group = true, order = 1, share = 0.67 },
        { classes = { "zen-twilight", "firefox-developer-edition" }, order = 2, share = 0.33 },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "work", "study" },
    },

    -- Obsidian + Linear: note-taking and issue tracking side by side.
    -- 50/50 split. The Obsidian settings window (title starts with
    -- "Settings") is a stray and floats.
    ["obsidian-linear"] = {
      blocks = {
        { classes = { "md.obsidian.Obsidian" }, order = 1, share = 0.5 },
        { classes = { "linear" }, order = 2, share = 0.5 },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "work", "study" },
    },

    -- Proton: mail client and password manager. 50/50 split. The Proton
    -- Pass companion opens alongside Proton Mail.
    proton = {
      blocks = {
        { classes = { "proton-mail" }, order = 1, share = 0.5 },
        {
          classes = { "Proton Pass" },
          order = 2,
          share = 0.5,
          spawn = { class = "Proton Pass", command = "proton-pass" },
        },
      },
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "work", "study", "gaming" },
    },

    -- Logs: the tmux log workspace. Empty blocks — the scene owns the
    -- workspace but does not declare tile geometry, so tmux controls its
    -- own layout. Follow-up: convert to LEO-308 terminal roles.
    logs = {
      blocks = {},
      barred = {},
      strays = "float",
      bindings = {},
      moods = { "work" },
    },
  },
}
