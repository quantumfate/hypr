-- Scene companions: the declared lifecycle of a window that exists only
-- because one of the scene's members does (docs/scenes.md's member `spawn`).
--
-- A companion is declared on the spawn-carrying block itself:
--
--   spawn = { class = "zen-twilight-media", command = "zen-twilight -P Media ..." }
--
-- `class` is the companion's identity (presence is derived from live windows,
-- never remembered); `command` is what runs the first time in; `max_spawns`
-- caps how many of `class` the engine keeps alive while the block has members
-- (default 1). This file decides only; carrying a decision out goes through
-- Hyprland events, which is also where the one piece of remembered state
-- lives: a spawn in flight, which a scan cannot yet see.
local spec_lib = require("hypr.scene.spec")

-- Where a deck parks the members it is not showing (hypr/scene/deck_provider).
-- Named here rather than required, so this module stays free of the provider.
local DECK_HOLD = "special:deck-hold"

-- Where the MODE parks a withdrawn scene's windows (hypr/hyprfocus/hold.lua).
local MODE_HELD = "special:hyprfocus-held"

-- Between dispatching a spawn and the companion's own open event there is a
-- window where a scan cannot yet see what was asked for, and a second
-- matching event in that gap would spawn a duplicate. The pending marker is
-- the only remembered fact. It is cleared by the caller — when the companion
-- maps, or when the scan converges on any other decision — and deliberately
-- does NOT use a timer: an in-flight spawn with a member-scene still alive is
-- one the user can reach with the same binds that spawned the member, and
-- presence is not state the desk keeps.
local M = {}

---@class Scene.CompanionDecision
---@field action "spawn"|"close"|"adopt"
---@field command string?
---@field address string? adopt: the parked window to take over
---@field addresses string?
---@field pending_key string the workspace+class key the caller tracks

---@class Scene.PendingIntent
---@field count number
---@field source string? address of the window focused when the intent was armed
---@field workspace string? workspace name the source was on

---What a workspace's spawn blocks each want, given live windows only.
---
---Presence is derived rather than tracked, so reload-safety is structural: a
---companion already on the desk satisfies the scan and no spawn re-issues,
---however often the config re-evaluates. The decision is per spawn-carrying
---block, keyed for the caller's pending marker by workspace+companion class —
---a block with several declared companions asks for each of them on its own.
---While members stand, a spawn is asked for only while the live count is
---below that entry's `max_spawns`; the last member leaving closes every
---companion whatever the cap, and a count at or above the cap never asks for
---another — the cap constrains what the engine opens, not what exists.
---@param spec Scene.Spec
---@param ws_name string
---@param windows HL.Window[] every live window on the desk
---@return Scene.CompanionDecision[] one entry per unsatisfied spawn block
function M.decisions(spec, ws_name, windows)
  local out = {}
  for _, block in ipairs(spec.blocks) do
    local spawns = block.spawns
    if spawns then
      -- Members are counted once for the whole block, not once per spawn:
      -- the presence that keeps companionship alive is the block's, and a
      -- spawn list of two shares that one fact rather than re-deriving it.
      local members = 0
      for _, w in ipairs(windows) do
        local name = w.workspace and w.workspace.name
        -- A member the deck has scrolled out of view stands on the deck's
        -- hold, not on the scene's workspace -- and it is still a member.
        -- Counting only the visible ones made a scroll read as "the last
        -- member left", which closed the companion; scrolling back opened it
        -- again. Every scroll of the block that carries the spawn churned a
        -- window closed and a new one open, forever.
        local on_scene = name == ws_name or name == DECK_HOLD
        if on_scene and spec_lib.class_matches(w.class, block.classes) then
          members = members + 1
        end
      end
      for _, spawn in ipairs(spawns) do
        -- A spawn declared `auto_start` keeps its companion alive whenever the
        -- scene is active, even before its member window has opened. The caller
        -- only converges companions for active scenes, so this does not leak a
        -- companion onto a withdrawn scene.
        local effective_members = spawn.auto_start and math.max(members, 1) or members

        local companions, parked = {}, {}
        for _, w in ipairs(windows) do
          local name = w.workspace and w.workspace.name
          if spec_lib.class_matches(w.class, { spawn.class }) and M.belongs(w, ws_name, spec) then
            -- Counted wherever it currently stands, not only once it is home: a
            -- claimed companion is stamped `slot:<ws>/...` on its open and only
            -- then moved, so counting workspace membership alone would read the
            -- window the engine just launched as absent and launch a second one
            -- in the gap.
            companions[#companions + 1] = w
          elseif name == MODE_HELD and spec_lib.class_matches(w.class, { spawn.class }) then
            -- A window of the companion's class the MODE parked, belonging to
            -- whichever scene it was withdrawn from. It is not this scene's --
            -- but it is the same application, and the one the launcher would
            -- hand back instead of opening another (verified live: a second
            -- `--new-window` on a profile whose only window is parked on a
            -- special workspace raises that window and opens nothing). So a
            -- spawn here would be a spawn that never arrives.
            parked[#parked + 1] = w
          end
        end
        if effective_members == 0 and #companions > 0 then
          local addresses = {}
          for _, companion in ipairs(companions) do
            addresses[#addresses + 1] = companion.address
          end
          out[#out + 1] = { action = "close", addresses = addresses, pending_key = M.key(ws_name, spawn.class) }
        elseif effective_members > 0 and #companions < spawn.max_spawns and parked[1] then
          -- Adopt rather than spawn: take the parked window into this scene and
          -- let the claim stamp its slot. The scene it was held for is
          -- withdrawn by definition (that is what the holding place means), and
          -- when a mode admits it again its own convergence opens one -- which
          -- works, because by then this one stands on a visible workspace.
          out[#out + 1] = {
            action = "adopt",
            address = parked[1].address,
            pending_key = M.key(ws_name, spawn.class),
          }
        elseif effective_members > 0 and #companions < spawn.max_spawns then
          -- The cap fills one per convergence, never in a burst: the caller's
          -- in-flight marker admits a single spawn at a time, and each spawned
          -- window's own open event re-converges the next. The count is derived
          -- from live windows, so a companion already on the desk — the user's,
          -- not the engine's — counts toward the cap and no extra spawn issues.
          out[#out + 1] = { action = "spawn", command = spawn.command, pending_key = M.key(ws_name, spawn.class) }
        end
      end
    end
  end
  return out
end

---Whether any of `spec`'s blocks names `class`.
---
---Block matching proper (`spec_lib.block_for`) also demands a slot tag where
---a block declares one, and a slot is stamped only once the window is home —
---which a parked companion is not. The question here is narrower and has no
---such precondition: does this scene speak for windows of this class.
---@param spec Scene.Spec
---@param class string?
---@return boolean
local function declares_class(spec, class)
  for _, block in ipairs(spec.blocks or {}) do
    if spec_lib.class_matches(class, block.classes) then
      return true
    end
  end
  return false
end

---Whether a live window belongs to `ws_name`'s scene for counting purposes:
---it stands on that workspace, or it carries a slot tag the scene stamped on
---it (`slot:<ws_name>/...`, `hypr/scene/identify.lua`). The tag is what makes
---the count honest between a claimed companion's open and the move that
---sends it home.
---@param w HL.Window
---@param ws_name string
---@return boolean
function M.belongs(w, ws_name, spec)
  if w.workspace and w.workspace.name == ws_name then
    return true
  end
  -- A deck scene parks the members its columns are not scrolled to on a hold
  -- workspace of its own. Such a companion is alive and belongs to this
  -- scene, but it stands nowhere this function used to look — so the scan
  -- read it as absent, the cap as unfilled, and opened another. Every
  -- convergence did it again: the browser window multiplied, one per pass,
  -- until the hold workspace held a stack of them.
  if spec and w.workspace and w.workspace.name == DECK_HOLD then
    return declares_class(spec, w.class)
  end
  for _, tag in ipairs(w.tags or {}) do
    if tag == "slot:" .. ws_name or tag:match("^slot:" .. ws_name:gsub("%p", "%%%0") .. "/") then
      return true
    end
  end
  return false
end

---The strongest decision for one pending key, after the caller's in-flight
---marker: a spawn already asked for is not asked for again, and companion
---windows that raced in between events converge once the marker is gone.
---@param decisions Scene.CompanionDecision[]
---@param pending table<string, Scene.PendingIntent>
---@return Scene.CompanionDecision[]
function M.filter(decisions, pending)
  local out = {}
  for _, decision in ipairs(decisions) do
    local entry = pending[decision.pending_key]
    local blocked = type(entry) == "table" and entry.count and entry.count > 0
    if decision.action == "close" or not blocked then
      out[#out + 1] = decision
    end
  end
  return out
end

---Arm the caller's in-flight marker for an in-flight spawn. It has no
---self-expiry: the events clear it (the companion maps, or the scene it was
---spawned for emptied), and a lost spawn still self-heals on the next event
---because the marker is only a duplicate guard, not a presence record.
---@param pending table<string, Scene.PendingIntent>
---@param key string
function M.expire(key, pending)
  local existing = pending[key]
  if type(existing) == "table" then
    existing.count = existing.count + 1
  else
    pending[key] = { count = 1 }
  end
end

---Workspace+class key for the pending marker.
---@param ws_name string
---@param class string
---@return string
function M.key(ws_name, class)
  return ws_name .. ":" .. class
end

return M
