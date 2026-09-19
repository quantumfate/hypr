local Store = require("hypr.lib.store")
local qs = require("hypr.lib.qs")
local watch = require("hypr.hyprfocus.watch")
local hyprfocus = require("hypr.hyprfocus")

-- Same desk every morning: whichever project carries `study` in projects.json
-- gets opened (its own window template decides the nvim window). Purely a
-- convenience on top of two stores that may not exist yet on a fresh
-- checkout — either one missing just means this step does nothing, silently.
local function open_study_project()
  local projects = Store.define("projects"):get("projects")
  local study_name = nil
  for name, meta in pairs(projects or {}) do
    if type(meta) == "table" and meta.study then
      study_name = name
      break
    end
  end
  if not study_name then
    return
  end

  -- Focus mode blocks distractions, not the thing it exists for — a leftover
  -- "focus" from last night just gets a heads-up, never a reason to skip this.
  local focus = Store.define("focus"):get()
  if focus and focus.mode == "focus" then
    hl.exec_cmd("notify-send 'focus' 'still on from last session' >/dev/null 2>&1")
  end

  -- The store now carries the project's path itself, so
  -- `,proj.sh open` takes the name directly — no scan or lookup needed here.
  hl.exec_cmd(("%s open %s >/dev/null 2>&1"):format(",proj.sh", ("%q"):format(study_name)))
end

hl.on("hyprland.start", function()
  -- Seed what is missing, reseed what is stale, before anything reads the
  -- declaration it might need (hypr/lib/maintenance.lua). Skipped under the
  -- nested e2e compositor: its fixtures ARE the declaration under test, and
  -- reseeding over them would test the shipped asset instead of the fixture.
  if os.getenv("QF_E2E") ~= "1" then
    require("hypr.lib.maintenance").run()
  end

  -- Login always enters `work`, unless the pointer names a still-running
  -- timed mode (docs/desktop-model.md "Pointer"). Runs under the nested e2e
  -- compositor too, deliberately: e2e's fixture pointer already starts at
  -- `work` (tests/e2e/fixtures/focus.pointer.json), so this is a no-op there
  -- by default and the scenario that overrides the fixture is what actually
  -- exercises this decision — skipping it under QF_E2E would leave the boot
  -- rule untested by the harness built to verify it live.
  hyprfocus.boot()

  -- The nested e2e compositor (tests/e2e/) starts nothing outside itself: no
  -- keymap, no shell, no project. The mode watcher is internal, so it stays.
  if os.getenv("QF_E2E") == "1" then
    watch.attach()
    return
  end
  hl.exec_cmd("setxkbmap dvorak-custom")
  -- Quickshell desktop shell (team panel + future widgets). Launched via
  -- `uwsm app` so it runs in its own systemd scope with the finalized session
  -- environment (uwsm manages this session). Replace any stale instance first.
  hl.exec_cmd("qs -c quantumfate kill >/dev/null 2>&1; uwsm app -- qs -c quantumfate >/dev/null 2>&1")
  -- Never leave the which-key overlay orphaned across a restart: even if a
  -- submap stack died with the old session, the new shell must start clear.
  qs.call("whichkey", "dismiss")
  -- Converge on the pointer's mode and keep watching it: the shell (or a
  -- later schedule) edits focus.json without the compositor, and a mode
  -- change that reaches only the pointer would leave the desk describing a
  -- mode it is not in. Event subscriptions rather than a timer — an idle
  -- desk pays stats, not ticks.
  watch.attach()
  open_study_project()
end)
