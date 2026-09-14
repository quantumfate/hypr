--- Which-key engine registry (LEO-222).
---
--- While submap.lua builds the submap tree it also records every node here,
--- so the renderer (Quickshell) gets the tree — parents, entries, keys, and
--- which entry leads to which child submap — instead of having to reconstruct
--- a hierarchy from a flat `hyprctl binds` dump. On config load the registry
--- is dumped as JSON to $XDG_STATE_HOME/whichkey.json, which the Quickshell
--- `Store { name: "whichkey" }` side mirrors reactively.
local M = {}

local json = require("hypr.lib.json")

local ROOT = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")

---@type table<string, string>
M.path = ROOT .. "/whichkey.json"

-- name -> { parent = string?, items = { { key, mods: string[], desc, group?, child? } } }
---@type table<string, WhichKeyNode>
local nodes = {}

---@param mods string[]?
---@return string[]
local function sanitize_mods(mods)
  local out = {}
  for _, m in ipairs(mods or {}) do
    out[#out + 1] = m
  end
  return out
end

---Record a submap node. `entries` are the raw SubmapEntry tables coming out of
---the a tree definition; groups (entries with `entries`) get a `child` so the
---renderer can follow nesting.
---@param name string
---@param parent string? parent submap name, or nil for a tree root
---@param entries SubmapEntry[]
function M.register(name, parent, entries)
  local node = { parent = parent or "", items = {} }
  for _, e in ipairs(entries) do
    local item = { key = e.key, mods = sanitize_mods(e.mods), desc = e.desc, group = false }
    if e.entries then
      item.group = true
      item.child = e.name or (name .. "-" .. e.key)
      item.desc = e.desc or item.child
    end
    node.items[#node.items + 1] = item
  end
  nodes[name] = node
end

---@param name string
---@return table? registered node
function M.node(name)
  return nodes[name]
end

---The whole registry, for serialization and tests.
---@return table<string, table>
function M.serialize()
  return nodes
end

---Rewrite the on-disk tree. Called once at config load (see init.lua), so a
---boot or a reload lands a fresh copy for the shell to pick up via FileView.
function M.dump()
  local f = io.open(M.path, "w")
  if not f then
    return
  end
  f:write(json.encode(nodes), "\n")
  f:close()
end

return M
