local Store = require("hypr.lib.store")
local qs = require("hypr.lib.qs")
local watch = require("hypr.hyprfocus.watch")
local hyprfocus = require("hypr.hyprfocus")

-- Wired here, as a plain top-level call, not from inside the
-- `hl.on("hyprland.start", ...)` handler below: that event fires once per
-- compositor process (verified live), so `watch.attach()`'s own
-- subscriptions never run again after the first `hyprctl reload` -- this
-- module's top-level statements do (every `require()` re-executes them), so
-- this is what keeps LEO-400's capture/restore hooks alive across every
-- later reload too.
require("hypr.hyprfocus.focus_history").attach()

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

  -- The study project's bring-up goes FIRST at real login: its launcher's
  -- focus dispatches then race the boot transition from the earliest possible
  -- moment, so they land inside the bracket (where they cannot interrupt the
  -- settle) instead of pulling focus off main after the veil has come down.
  -- Best-effort like boot itself: a project problem must never abort the
  -- session start.
  if os.getenv("QF_E2E") ~= "1" then
    local opened, open_err = pcall(open_study_project)
    if not opened then
      print("open_study_project failed, continuing session start: " .. tostring(open_err))
    end
  end

  -- Login always enters `work`, unless the pointer names a still-running
  -- timed mode (docs/desktop-model.md "Pointer"). Runs under the nested e2e
  -- compositor too, deliberately: e2e's fixture pointer already starts at
  -- `work` (tests/e2e/fixtures/focus.pointer.json), so this is a no-op there
  -- by default and the scenario that overrides the fixture is what actually
  -- exercises this decision — skipping it under QF_E2E would leave the boot
  -- rule untested by the harness built to verify it live.
  -- Non-fatal: an error here used to abort the whole `hyprland.start`
  -- handler, and everything below it -- the keymap, the shell, the whichkey
  -- reset -- simply never ran. A live monitor/workspace race inside `place()`
  -- ("No monitor, can't find ws to target") was enough to leave the desk with
  -- no bar at all after a reboot, which reads as "the bar crashed" when in
  -- fact it was never launched. Boot placement is best-effort; the rest of
  -- the session is not.
  local booted, boot_err = pcall(hyprfocus.boot)
  if not booted then
    print("hyprfocus.boot failed, continuing session start: " .. tostring(boot_err))
  end

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
end)
