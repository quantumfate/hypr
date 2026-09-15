--- Which-key engine registry (LEO-222).
---
--- While submap.lua builds the submap tree it also records every node here,
--- so the renderer (Quickshell) gets the tree — parents, entries, keys, and
--- which entry leads to which child submap — instead of having to reconstruct
--- a hierarchy from a flat `hyprctl binds` dump. On config load the registry
--- is dumped as JSON to $QF_STORE/whichkey.json, which the Quickshell
--- `Store { name: "whichkey" }` side mirrors reactively.
local M = {}

local json = require("hypr.lib.json")

-- The store file the Quickshell `Store { name = "whichkey" }` side mirrors,
-- under the shared quantum-store directory (QF_STORE). Located here rather
-- than through the store handle because the dump never re-reads it — writes
-- only — and specs stub the handle's module wholesale, so depending on it
-- would make every stub carry more than it names.
M.path = (
  os.getenv("QF_STORE")
  or ((os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/quantum-store")
) .. "/whichkey.json"

-- One registry node as the Quickshell side reads it.
---@class WhichKeyItem
---@field key string
---@field mods string[]
---@field desc string
---@field group boolean
---@field child? string

---@class WhichKeyNode
---@field parent string
---@field items WhichKeyItem[]

-- name -> { parent, items }
---@type table<string, WhichKeyNode>
local nodes = {}

-- The root node's key: not a submap the compositor enters, but the registry's
-- one entry point for the binds outside any submap, so the full cheatsheet
-- and the overlay read the SAME document (LEO-268). WhichKey.js's nodeFor
-- maps "reset" to null, so the overlay behaves exactly as before.
local RESET = "reset"

---@param mods string[]?
---@return string[]
local function sanitize_mods(mods)
  local out = {}
  for _, m in ipairs(mods or {}) do
    out[#out + 1] = m
  end
  return out
end

---Record a described bind that lives outside any submap (the root). The
---"reset" node holds them: the cheatsheet's root view parses this node with
---the same by-construction guarantee the submap trees carry — the shortcuts
---it renders are exactly the shortcuts that work.
---@param key string
---@param mods string[]
---@param desc string
function M.record_root(key, mods, desc)
  if not key or not desc then
    return
  end
  local node = nodes[RESET]
  if not node then
    node = { parent = "", items = {} }
    nodes[RESET] = node
  end
  node.items[#node.items + 1] = { key = key, mods = sanitize_mods(mods), desc = desc, group = false }
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
    elseif e.opens then
      -- A leaf that only enters another submap: the renderer needs to know
      -- its destination so a withheld tree can take its leaf down too.
      -- Treat it as a group in the overlay so the nesting affordance renders
      -- (LEO-327): pressing the key enters the submap and the menu follows.
      item.group = true
      item.child = e.opens
    end
    node.items[#node.items + 1] = item
  end
  nodes[name] = node
end

---@param name string
---@return WhichKeyNode?
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
---
---The overlay's own leaves are the special case that makes this a per-item
---filter rather than a per-node one: they live in an always-enabled tree, but
---a leaf whose destination is a withheld submap is a door the mode took away,
---and the registry's `opens` marks exactly those. The registry itself is never
---mutated — a dump narrows a copy, so re-admitting a tree brings its leaf
---back on the next one.
---@param admitted table<string, true>? nil means everything is loaded
function M.dump(admitted)
  -- The store directory may not exist on a fresh machine; the write is part
  -- of config load, which is the only thing that guarantees the caller runs
  -- Lua, so it is fair to create it here rather than require a seed step.
  os.execute(("mkdir -p %q"):format(M.path:match("^(.*)/[^/]+$")))
  local f = io.open(M.path, "w")
  if not f then
    return
  end
  local out = nodes
  if admitted then
    out = {}
    for name, node in pairs(nodes) do
      -- The registry's root node ("reset") holds the binds outside any submap;
      -- in the admission grammar that tree is called "root". Map the name so
      -- the cheatsheet keeps its top-level entries when root is loaded.
      local tree = tree_of(name)
      if tree == RESET then
        tree = "root"
      end
      if admitted[tree] then
        local rendered = { parent = node.parent, items = {} }
        for _, item in ipairs(node.items) do
          -- An `opens` leaf answers for its destination tree; a group's child
          -- is its own nesting and trivially admitted with its tree.
          local child_tree = item.child and tree_of(item.child) or nil
          if not item.child or admitted[child_tree] then
            rendered.items[#rendered.items + 1] = item
          end
        end
        out[name] = rendered
      end
    end
  end
  f:write(json.encode(out), "\n")
  f:close()
end

return M
