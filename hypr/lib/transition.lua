-- Suspend compositor animations and focus disruptions for the duration of a
-- mode apply, and publish the transition so the shell can present it
-- (LEO-423).
--
-- A mode apply moves workspaces across monitors, parks and restores windows,
-- and re-homes strays. Every one of those dispatches carries a live animation,
-- so the whole apply plays out as a swipe across the desk. None of it is worth
-- watching: geometry only matters once it has settled, and a mid-flight frame
-- is exactly what reads as a glitch. Suspending animations for the apply makes
-- every move land at its final position in one frame. The same bracket holds
-- focus still: activation requests are ignored and newly opened windows map
-- unfocused, so nothing interrupts the landing on the mode's main scene.
--
-- The visible transition is the shell's, not the compositor's. Quickshell
-- draws a full-screen scrim whose QML fade is client-side and therefore
-- unaffected by this switch. This module publishes when the work starts and
-- stops on the shared store so that scrim can bracket it; `hypr/lib/store.lua`
-- and the shell's `services/Store.qml` are the seam.
--
-- A bracket can never wedge the desk: every `begin` arms a failsafe well past
-- the bracket's legitimate lifetime, and if `finish` never ran the failsafe
-- force-settles — settings restored, guard withdrawn, apply guard released
-- (via the hook `M.on_force_settle` registers), the store told the bracket is
-- over. The settle callback deliberately does NOT run then: the desk may be
-- half-placed, and landing on main would be a guess.
local store = require("hypr.lib.store")
local hypr = require("hypr.lib.hypr")

local M = {}

local STORE = "hyprfocus.transition"

-- How long the veil stays up on a genuine mode transition: the queued moves
-- need to land, and the shell draws its veil (opaque blurred wallpaper plus
-- the mode label) for the whole bracket so the user never watches the
-- rearrangement. Long enough to hide the mess, not just the first frame —
-- the tail also covers the stragglers (drawer bring-up spawns, late maps)
-- that would otherwise flash onto a half-placed desk. A plain apply (config
-- load, `hyprctl reload`) keeps animations off only long enough for its own
-- queued moves to land, and shows no veil.
local VEIL_MS = 4200
local SETTLE_MS = 400
-- The last line of defence against a stuck veil. A genuine transition's whole
-- legitimate lifetime from `begin` is the veil lead plus its phased apply plus
-- the settle span — well under this. If the bracket is still up when the
-- failsafe fires, `finish` never ran (a phased step's timer died, or a nested
-- apply refused mid-chain), and leaving the bracket standing costs the user
-- the desk: animations stay suspended, the open-focus guard stays raised, the
-- shell's veil stays mapped, and every later apply refuses as "already in
-- progress". The failsafe force-settles: no settle callback (the desk may be
-- half-placed — landing on main then would be a guess), settings restored,
-- guard withdrawn, the store told the bracket is over.
local FAILSAFE_MS = 8000

-- The named catch-all rule that keeps newly opened windows from taking focus
-- for the duration of a bracket. Hyprland 0.56 has no config toggle for
-- open-time focus (`misc.new_window_takes_focus` is gone), but a named rule
-- can be re-declared at runtime: the same name is reused, so begin enables
-- the guard and finish withdraws it — no handle needed, no config reload.
-- Verified live (nested): windows opened under `no_focus` do not steal focus
-- and become focusable again the moment the rule is disabled.
--
-- Two quirks of this build's rule engine, both spiked live, shape the code:
-- a rule whose FIRST registration follows a dynamic `hl.config` call is
-- inert, so the name must be registered at config load (below, at module
-- level) with runtime only ever re-declaring it; and an explicit
-- `enabled = true` in the declaration makes its effects inert, so the raise
-- re-declaration omits the key (absent defaults to enabled) while the
-- withdraw carries `enabled = false`.
local GUARD_RULE = "hyprfocus-transition-guard"

-- One-time registration at config load: disabled, so it matches nothing it
-- could affect, but the name exists before the first dynamic `hl.config`.
pcall(function()
  hl.window_rule({
    name = GUARD_RULE,
    enabled = false,
    match = { class = ".*" },
    no_focus = true,
  })
end)

-- Bumped on every begin, so a settled transition cannot be re-enabled by an
-- older timer after a newer transition has started.
local generation = 0
local timer = nil
local failsafe = nil
-- Whether a transition is currently bracketed (begin without a settled
-- finish). Separate from `timer`: begin brackets immediately, the timer only
-- exists once finish has been called.
local bracketed = false
-- Whether the bracket is a genuine mode transition the shell should veil, as
-- opposed to a reload's apply.
local veiled = false
-- Run once when the transition settles. A mode transition uses it to land on
-- the mode's main scene LAST, after every queued move has landed — focusing
-- main up front would let a later move or activation pull the user back off it.
local settled_cb = nil

-- How long the current bracket tells the shell to count for, and the mode it
-- was begun with. Stored so the matching finish — or a failsafe — publishes
-- the same identity even if `veiled` has flipped.
local current_duration_ms = SETTLE_MS
local current_mode = "work"

-- Registered by the apply driver (hyprfocus/init.lua): a force-settle must
-- also release the apply guard, or every later mode change refuses as
-- "already in progress" — which is exactly how a stuck veil used to trap the
-- recovery path too.
local force_settle_hook = nil

---Register the one callback a force-settle runs beyond its own state cleanup.
---@param cb fun()
function M.on_force_settle(cb)
  force_settle_hook = cb
end

-- Everything the compositor may do ON ITS OWN that moves focus, the
-- workspace or the pointer while a transition rearranges the desk -- the
-- whole list of what a graceful transition needs, in one place. Each entry is
-- switched to its quiet value when a bracket begins and restored to whatever
-- was live before when the grace after the landing ends, so a reader never
-- has to reverse-engineer which later correction guards against which
-- compositor behaviour.
--
-- Beside these, the `GUARD_RULE` window rule keeps every window that maps
-- inside the bracket from taking focus on open: Hyprland 0.56 has no config
-- toggle for that (`misc.new_window_takes_focus` is gone).
---@type { key: string, quiet: any, why: string }[]
M.QUIET = {
  {
    key = "animations.enabled",
    quiet = false,
    why = "every move lands in one frame instead of swiping across the desk",
  },
  {
    key = "misc.focus_on_activate",
    quiet = false,
    why = "an app activating itself (xdg-activation) cannot take focus off the landing",
  },
  {
    key = "misc.mouse_move_focuses_monitor",
    quiet = false,
    why = "the pointer -- including the seat's own warp -- cannot move monitor focus under the landing",
  },
  {
    key = "input.follow_mouse",
    quiet = 0,
    why = "a window sliding under a resting pointer cannot take focus",
  },
  {
    key = "binds.workspace_back_and_forth",
    quiet = false,
    why = "landing on main while main is already shown cannot bounce to the previous workspace",
  },
  {
    key = "binds.allow_workspace_cycles",
    quiet = false,
    why = "the same bounce, through workspace history",
  },
}

-- How long the desk stays quiet after the landing. The CLI half (services,
-- theme) starts at the landing, and what it starts maps seconds later -- the
-- obsidian suite is the case that bit. Inside the grace those windows open
-- unfocused and cannot activate, so the landing holds without a later check
-- having to put it back. The veil is already down; nothing visible waits on
-- this.
local GRACE_MS = 6000
M.GRACE_MS = GRACE_MS

-- The live values the quiet set replaced, by key, captured by the first begin
-- of a chain (nil where the runtime refused the key: that one is left alone).
---@type table<string, any>
local priors = {}
-- Whether the quiet set and the open-focus guard are in force. Outlives
-- `bracketed`: the bracket ends at the landing, the quiet at the grace's end.
local quieted = false
-- The grace timer, so a newer bracket can take the quiet over.
local grace = nil

---Read a live config value, or nil when the runtime refuses the key.
---@param key string
---@return any
local function read_config(key)
  local ok, value = pcall(function()
    return hl.get_config(key)
  end)
  if ok then
    return value
  end
  return nil
end

---A nested `hl.config` patch setting each quiet key to `pick(entry)`.
---@param pick fun(entry: { key: string, quiet: any }): any
---@return table
local function patch_of(pick)
  local patch = {}
  for _, entry in ipairs(M.QUIET) do
    local value = pick(entry)
    if value ~= nil then
      local section, name = entry.key:match("^([^.]+)%.(.+)$")
      patch[section] = patch[section] or {}
      patch[section][name] = value
    end
  end
  return patch
end

---Put the desk into its quiet state: capture what is live (once per chain --
---a second begin would read the already-quiet values back as "prior"), raise
---the open-focus guard, apply the quiet set.
local function raise_quiet()
  if grace then
    pcall(function()
      grace:set_enabled(false)
    end)
    grace = nil
  end
  if not quieted then
    priors = {}
    for _, entry in ipairs(M.QUIET) do
      priors[entry.key] = read_config(entry.key)
    end
  end
  quieted = true
  pcall(function()
    -- Raised before the config update: a rule re-declared right after an
    -- `hl.config` can land inert on this build.
    hl.window_rule({
      name = GUARD_RULE,
      match = { class = ".*" },
      no_focus = true,
    })
  end)
  pcall(function()
    hl.config(patch_of(function(entry)
      return entry.quiet
    end))
  end)
end

---Return the desk to what it was: withdraw the guard, restore every captured
---value.
local function release_quiet()
  if grace then
    pcall(function()
      grace:set_enabled(false)
    end)
    grace = nil
  end
  if not quieted then
    return
  end
  quieted = false
  pcall(function()
    hl.window_rule({ name = GUARD_RULE, enabled = false })
  end)
  pcall(function()
    hl.config(patch_of(function(entry)
      return priors[entry.key]
    end))
  end)
end

---@param active boolean
---@param mode string
---@param veil boolean
---@param duration_ms number?
local function publish(active, mode, veil, duration_ms)
  local ok, handle = pcall(store.define, STORE)
  if not ok then
    return
  end
  local ok2, err2 = pcall(function()
    -- `present` is the veil, and only while the bracket is actually up: a
    -- settled transition publishes `active = false`, so the shell unmaps.
    -- `duration_ms` lets the shell draw progress that counts the actual
    -- bracket length (LEO-423 follow-up).
    handle:set({
      active = active,
      present = active and veil,
      mode = mode,
      seq = generation,
      duration_ms = duration_ms,
      started_at = active and (os.time() * 1000) or nil,
    })
  end)
  if not ok2 then
    pcall(function()
      require("hypr.lib.trace").emit({
        stage = "transition",
        event = "publish_failed",
        decision = "fail",
        reason = tostring(err2),
        mode = mode,
      })
    end)
  end
end

---Cancel the failsafe timer, if one is armed.
local function disarm_failsafe()
  if failsafe then
    pcall(function()
      failsafe:set_enabled(false)
    end)
    failsafe = nil
  end
end

---Force-settle a bracket whose `finish` never came.
---
---The settle callback STILL RUNS. It used to be dropped here on the grounds
---that a half-placed desk is no place to land — but the landing is a
---workspace focus on the mode's own declared main scene, which is a fact
---about the mode, not about how far the placing got. Dropping it meant the
---one case where the desk is least predictable was also the one case where
---focus was left wherever it happened to be, and "where am I after a mode
---swap" stopped having an answer. Deterministic beats tidy: a transition
---always ends on main (the user's own standing requirement, 2026-09-25).
---
---The settings, the guard and the published state all return to rest, so the
---user gets a working desk back and the next mode change is not refused.
---@param gen integer the generation this failsafe was armed under
local function force_settle(gen)
  failsafe = nil
  if not bracketed or gen ~= generation then
    return
  end
  if timer then
    pcall(function()
      timer:set_enabled(false)
    end)
    timer = nil
  end
  -- Land first, while the open-focus guard is still raised and activation
  -- focus is still off -- the same order the legitimate settle uses, so a
  -- window mapping in this instant cannot steal the landing.
  local cb = settled_cb
  settled_cb = nil
  if cb then
    pcall(cb)
  end
  bracketed = false
  -- No grace: a bracket that had to be forced is not trusted to stay quiet.
  release_quiet()
  publish(false, current_mode, veiled, current_duration_ms)
  if force_settle_hook then
    pcall(force_settle_hook)
  end
  pcall(function()
    require("hypr.lib.trace").emit({
      stage = "transition",
      event = "failsafe_settled",
      decision = "force",
      reason = "finish never ran within " .. FAILSAFE_MS .. " ms of begin",
    })
  end)
end

---Suspend animations and mark the transition active. Returns the generation,
---which the matching `finish` ignores itself against.
---
---`veil` marks a genuine mode transition the shell should cover with its
---full-screen veil; a plain apply (config load, `hyprctl reload`) passes false
---and keeps the animation suspension only. `on_settled` runs once when the
---bracket settles (nil for a reload), so a transition can land on its main
---scene after the moves rather than in front of them.
---
---`duration_ms` overrides the default veil/settle span published to the shell.
---Use it when the caller knows the bracket's total lifetime (e.g. lead +
---phased apply + settle) so the shell countdown matches the actual veil.
---@param mode string
---@param veil boolean?
---@param on_settled fun()?
---@param duration_ms number?
---@return integer
-- Exported spans so callers can publish the bracket's total lifetime.
M.VEIL_MS = VEIL_MS
M.SETTLE_MS = SETTLE_MS

function M.begin(mode, veil, on_settled, duration_ms)
  generation = generation + 1
  disarm_failsafe()
  -- The latest apply in a chain owns the bracket's identity: a converge landing
  -- inside a reload's bracket upgrades it to a veiled transition. A reload
  -- landing inside a transition's bracket would normally downgrade it, but
  -- once the user has seen a veil we keep it up: downgrading mid-bracket makes
  -- the transition flicker off and can leave focus in the wrong place. The
  -- applying guard already prevents a second full apply, so this mostly
  -- hardens against races and direct bracket callers.
  if not (bracketed and veiled) then
    veiled = veil == true
  end
  current_duration_ms = duration_ms or (veiled and VEIL_MS or SETTLE_MS)
  current_mode = mode
  settled_cb = on_settled
  bracketed = true
  -- The desk goes quiet for the whole bracket and the grace after it
  -- (`M.QUIET`); a begin inside a running grace takes the quiet over.
  raise_quiet()
  publish(true, mode, veiled, current_duration_ms)
  pcall(function()
    require("hypr.lib.trace").emit({
      stage = "transition",
      event = "begin",
      decision = veiled and "veil" or "settle",
      mode = mode,
      duration_ms = current_duration_ms,
      generation = generation,
    })
  end)
  -- Arm the failsafe AFTER the publish, capturing this begin's generation: a
  -- later begin re-arms it, and an earlier settle disarms it, so it can only
  -- ever fire against a bracket that genuinely outlived its own lifetime.
  -- pcall: a timer that refuses to arm must not break the transition itself.
  local gen = generation
  pcall(function()
    failsafe = hypr.oneshot(FAILSAFE_MS, function()
      force_settle(gen)
    end)
  end)
  return generation
end

---Report that the apply behind this bracket is still advancing, which pushes
---the failsafe back by its full span.
---
---The failsafe measures the bracket against a fixed 8s, and an apply's own
---work is not fixed: restoring ten held windows across two deck scenes takes
---as long as it takes. A heavy swap therefore tripped the wedge-guard while
---it was still working normally -- and force-settling drops the settle
---callback, so the landing on the mode's main scene and the companion
---reconvergence were silently skipped on exactly the swaps that moved the
---most (live, 2026-09-24). Pet it from each phase and the guard measures what
---it is actually there for: not "is this taking long" but "has this stopped".
function M.progress()
  if not bracketed or not failsafe then
    return
  end
  local gen = generation
  pcall(function()
    failsafe:set_timeout(FAILSAFE_MS)
  end)
  -- A handle that cannot be re-armed is replaced outright, so the guard is
  -- never simply lost.
  if not failsafe then
    pcall(function()
      failsafe = hypr.oneshot(FAILSAFE_MS, function()
        force_settle(gen)
      end)
    end)
  end
end

---Restore animations once the queued moves have settled. A transition that
---began meanwhile owns its own settle; this timer bows out at the generation
---guard and never re-enables underneath it.
---@param mode string
function M.finish(mode)
  local gen = generation
  local span = veiled and VEIL_MS or SETTLE_MS
  pcall(function()
    require("hypr.lib.trace").emit({
      stage = "transition",
      event = "finish",
      decision = veiled and "veil" or "settle",
      mode = mode,
      settle_ms = span,
      generation = gen,
    })
  end)
  if timer then
    pcall(function()
      timer:set_enabled(false)
    end)
    timer = nil
  end
  local handle
  handle = hypr.oneshot(span, function()
    if timer == handle then
      timer = nil
    end
    if gen ~= generation then
      return
    end
    -- A legitimate settle: the failsafe is stood down for this bracket.
    disarm_failsafe()
    -- Land on main while the bracket is still active: activation focus is
    -- still off and the open-focus guard is still raised, so a window that
    -- tries to interrupt the landing is ignored. Restoring settings first
    -- would let an activation request or newly mapped window steal focus
    -- between the restore and the focus dispatch.
    local cb = settled_cb
    settled_cb = nil
    if cb then
      pcall(cb)
    end
    bracketed = false
    -- The veil comes down now; the quiet holds for the grace, so whatever the
    -- landing started (the CLI half's services) maps without taking focus.
    -- A newer begin cancels this timer and keeps the quiet as its own.
    pcall(function()
      grace = hypr.oneshot(GRACE_MS, function()
        grace = nil
        if gen == generation and not bracketed then
          release_quiet()
        end
      end)
    end)
    if not grace then
      release_quiet()
    end
    publish(false, mode, veiled, current_duration_ms)
    pcall(function()
      require("hypr.lib.trace").emit({
        stage = "transition",
        event = "settled",
        decision = "done",
        mode = mode,
        generation = gen,
      })
    end)
  end)
  timer = handle
end

---Whether a transition is currently bracketed. For logs and specs.
---@return boolean
function M.active()
  return bracketed
end

---Drop the settle callback without running it.
---
---Nothing in the apply path calls this any more: a failed phase used to, and
---the result was a mode swap that left focus wherever it was, which is the
---non-determinism the desk is not allowed to have. Kept for a caller that
---genuinely must not land (none today), so the capability is explicit rather
---than re-invented.
function M.clear_settled()
  settled_cb = nil
end

return M
