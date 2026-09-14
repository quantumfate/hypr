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

---The tree a node belongs to: the outermost submap above it. A mode admits or
---withholds whole trees, so everything nested under `dofus` answers "dofus".
---@param name string
---@return string
local function tree_of(name)
  local seen = {}
  local current = name
  while true do
    local node = nodes[current]
    local parent = node and node.parent
    if not parent or parent == "" or seen[parent] then
      return current
    end
    seen[current] = true
    current = parent
  end
end

---Rewrite the on-disk tree. Called at config load, and again whenever the set
---of loaded binding trees changes.
---
---`admitted`, when given, names the trees whose binds are enabled; everything
---else is omitted. That is what makes the cheatsheet accurate by construction
---rather than by filtering: the tree it renders IS the set of keys that work,
---so it cannot list an entry that would do nothing when pressed.
---@param admitted table<string, true>? nil means everything is loaded
function M.dump(admitted)
  local f = io.open(M.path, "w")
  if not f then
    return
  end
  local out = nodes
  if admitted then
    out = {}
    for name, node in pairs(nodes) do
      if admitted[tree_of(name)] then
        out[name] = node
      end
    end
  end
  f:write(json.encode(out), "\n")
  f:close()
end

return M
