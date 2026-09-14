-- Scene companions: the declared lifecycle of a window that exists only
-- because one of the scene's members does (docs/scenes.md's member `spawn`).
--
-- A companion is declared on the spawn-carrying block itself:
--
--   spawn = { class = "zen-gaming-media", command = "zen-twilight ..." }
--
-- `class` is the companion's identity (presence is derived from live windows,
-- never remembered); `command` is what runs the first time in. This file
-- decides only; carrying a decision out goes through Hyprland events, which
-- is also where the one piece of remembered state lives: a spawn in flight,
-- which a scan cannot yet see.
local spec_lib = require("hypr.scene.spec")

-- Between dispatching a spawn and the companion's own open event there is a
-- window where a scan cannot yet see what was asked for, and a second
-- matching event in that gap would spawn a duplicate. The pending marker is
-- the only remembered fact, and its lifetime is finite: presence is not
-- state the desk keeps.
local PENDING_MS = 4000

local M = {}

---@class Scene.CompanionDecision
---@field action "spawn"|"close"
---@field command string?
---@field addresses string?
---@field pending_key string the workspace+class key the caller tracks

---What a workspace's spawn blocks each want, given live windows only.
---
---Presence is derived rather than tracked, so reload-safety is structural: a
---companion already on the desk satisfies the scan and no spawn re-issues,
---however often the config re-evaluates. The decision is per spawn-carrying
---block, keyed for the caller's pending marker by workspace+companion class.
---@param spec Scene.Spec
---@param ws_name string
---@param windows HL.Window[] every live window on the desk
---@return Scene.CompanionDecision[] one entry per unsatisfied spawn block
function M.decisions(spec, ws_name, windows)
  local out = {}
  for _, block in ipairs(spec.blocks) do
    local spawn = block.spawn
    if spawn then
      local members, companions = 0, {}
      for _, w in ipairs(windows) do
        local name = w.workspace and w.workspace.name
        if name == ws_name then
          if spec_lib.class_matches(w.class, block.classes) then
            members = members + 1
          elseif spec_lib.class_matches(w.class, { spawn.class }) then
            companions[#companions + 1] = w
          end
        end
      end
      if members == 0 and #companions > 0 then
        local addresses = {}
        for _, companion in ipairs(companions) do
          addresses[#addresses + 1] = companion.address
        end
        out[#out + 1] = { action = "close", addresses = addresses, pending_key = M.key(ws_name, spawn.class) }
      elseif members > 0 and #companions == 0 then
        out[#out + 1] = { action = "spawn", command = spawn.command, pending_key = M.key(ws_name, spawn.class) }
      end
    end
  end
  return out
end

---The strongest decision for one pending key, after the caller's in-flight
---marker: a spawn already asked for is not asked for again, and companion
---windows that raced in between events converge once the marker is gone.
---@param decisions Scene.CompanionDecision[]
---@param pending table<string, true>
---@return Scene.CompanionDecision[]
function M.filter(decisions, pending)
  local out = {}
  for _, decision in ipairs(decisions) do
    if decision.action == "close" or not pending[decision.pending_key] then
      out[#out + 1] = decision
    end
  end
  return out
end

---The caller's pending marker for an in-flight spawn has a finite lifetime:
---a lost spawn self-heals on the next event instead of leaving the desk
---believing a companion is coming forever.
---@param pending table<string, true>
---@param key string
---@param timer fun(ms: integer, cb: fun()) the one-shot scheduling primitive, injected for testability
function M.expire(timer, key, pending)
  pending[key] = true
  timer(PENDING_MS, function()
    pending[key] = nil
  end)
end

---Workspace+class key for the pending marker.
---@param ws_name string
---@param class string
---@return string
function M.key(ws_name, class)
  return ws_name .. ":" .. class
end

return M
