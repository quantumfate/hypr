-- store.lua — generic reactive JSON state, shared between the Hyprland Lua
-- config and the Quickshell UI.
--
--   $QF_STORE/<name>.json          <->   Store handle (this)   <->   Quickshell
--
-- QF_STORE is the shared quantum-store directory every runtime keeps its
-- state in (default $XDG_STATE_HOME/quantum-store; env-hyprland exports it so
-- every consumer answers the same). A handle keeps a decoded copy in RAM
-- and refreshes it only when the file's mtime changes, so every read gets the
-- newest on-disk state without a config reload and without re-parsing on every
-- access. Writes are atomic (tmp + rename), which bumps mtime so the
-- Quickshell side's FileView watch reacts. See hypr/lib/json.lua for the codec
-- and services/Store.qml in the quickshell repo for the mirror on the QML side.
--
-- Migration reads one step back: a handle whose store does not exist yet at
-- $QF_STORE but still exists at the pre-store-directory location
-- ($XDG_STATE_HOME/<name>.json) adopts that document and writes forward —
-- the first change to a store migrates it, and no session start clause is
-- needed for the compositor's half.
--
-- Usage:
--   local Store = require("hypr.lib.store")
--   local team = Store.define("dofus/team")     -- one shared handle per path
--   team:get()                 -- whole decoded table (mtime-cached)
--   team:get("selected")       -- a top-level key
--   team:update(function(t) t.selected = "duo"; return t end)  -- mutate + save
--   team:set({ selected = "duo" })              -- shallow-merge patch + save
--   team:reload()              -- force a re-read

local json = require("hypr.lib.json")

local M = {}

---The shared store root. QF_STORE names it; the default is one dir deeper
---than where the stores lived before it existed, which is also what the
---fallback read below migrates from.
---@return string
local function ROOT()
  return os.getenv("QF_STORE")
    or ((os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/quantum-store")
end

---Where the store lived before quantum-store existed: the one step back a
---handle's migration reads.
---@return string
local function LEGACY_ROOT()
  return os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
end

-- One handle per resolved path, so all modules/bindings share a cache.
---@type table<string, Store.Handle>
local handles = {}

-- Stores exempt from legacy-document fallback: a missing file must leave the
-- engine inert, never resurrect an old document (the quickshell counterpart's
-- equivalent fallback did exactly that for hyprfocus.json).
local NO_LEGACY = { hyprfocus = true }

---@param cmd string
---@return string
local function shell(cmd)
  local h = io.popen(cmd)
  if not h then
    return ""
  end
  local out = h:read("*a") or ""
  h:close()
  return out
end

---@param path string
---@return string mtime seconds, or "" if the file is missing
local function file_mtime(path)
  return (shell(("stat -c %%Y %q 2>/dev/null"):format(path)):gsub("%s+$", ""))
end

---@param path string
---@return string? contents
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

-- Pretty-print so the file stays human- and git-diff-friendly, matching the
-- 2-space output the Quickshell side writes with JSON.stringify(v, null, 2).
---@param v any
---@param indent string?
---@return string
local function pretty(v, indent)
  indent = indent or ""
  if type(v) ~= "table" then
    return json.encode(v)
  end
  local inner = indent .. "  "
  -- Array iff it has a [1] (our empty states are objects, so prefer {}).
  if rawget(v, 1) ~= nil then
    local parts = {}
    for _, item in ipairs(v) do
      parts[#parts + 1] = inner .. pretty(item, inner)
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
  end
  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  if #keys == 0 then
    return "{}"
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = inner .. json.encode(k) .. ": " .. pretty(v[k], inner)
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

---@param path string
---@param text string
---@return boolean ok
local function atomic_write(path, text)
  -- mktemp in the same dir so the rename is atomic (same filesystem).
  local dir = path:match("^(.*)/[^/]+$") or "."
  local tmp = shell(("mkdir -p %q && mktemp %q/.store.XXXXXX 2>/dev/null"):format(dir, dir)):gsub("%s+$", "")
  if tmp == "" then
    return false
  end
  local f = io.open(tmp, "w")
  if not f then
    return false
  end
  f:write(text)
  f:close()
  os.rename(tmp, path)
  return true
end

---@class Store.Handle
---@field name string
---@field path string
---@field legacy string? where the store lived before the store directory existed
local Handle = {}
Handle.__index = Handle

-- Re-read from disk if the file changed (or force). Returns the cached table.
-- A missing store whose legacy file still exists adopts it in place of an
-- empty state: the document heads to the new location on the next write, and
-- a hand-moved file is picked up without any special step.
---@param force boolean?
---@return table
function Handle:reload(force)
  local mt = file_mtime(self.path)
  if not force and mt ~= "" and mt == self._mtime and self._data then
    return self._data
  end
  local raw = read_file(self.path)
  if (not raw or raw == "") and self.legacy and file_mtime(self.legacy) ~= "" then
    raw = read_file(self.legacy)
  end
  if not raw or raw == "" then
    self._data = self._data or {}
    return self._data
  end
  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == "table" then
    self._data = decoded
    self._mtime = mt
  end
  return self._data or {}
end

-- The store's on-disk mtime, refreshed like get(). A caller that memoizes its
-- own derived state (e.g. hypr/scene/spec.lua normalizing scenes) keys its
-- cache on this, so a store edit invalidates it without a config reload.
---@return string
function Handle:mtime()
  self:reload()
  return self._mtime or ""
end

-- Get the whole table, or drill into keys: get("teams", "pioneer").
---@param ... string|integer keys to index into, in order
---@return any
function Handle:get(...)
  local v = self:reload()
  for i = 1, select("#", ...) do
    if type(v) ~= "table" then
      return nil
    end
    v = v[select(i, ...)]
  end
  return v
end

-- Replace the whole table and persist. Bumps mtime -> Quickshell reacts.
---@param data table
function Handle:put(data)
  if atomic_write(self.path, pretty(data) .. "\n") then
    self._data = data
    self._mtime = nil -- force a stat-confirmed reload next time
  end
end

-- Mutate via a function that receives (and returns) the current table.
---@param fn fun(t: table): table
function Handle:update(fn)
  local t = self:reload(true)
  self:put(fn(t) or t)
end

-- Shallow-merge a patch of top-level keys, then persist.
---@param patch table
function Handle:set(patch)
  self:update(function(t)
    for k, v in pairs(patch) do
      t[k] = v
    end
    return t
  end)
end

-- Define (or fetch the shared handle for) a named store. `name` may contain
-- slashes; it resolves to $QF_STORE/<name>.json, with the pre-store-directory
-- location as the migration read.
---@param name string
---@return Store.Handle
function M.define(name)
  local path = ROOT() .. "/" .. name .. ".json"
  if not handles[path] then
    local legacy = nil
    if not NO_LEGACY[name] then
      legacy = LEGACY_ROOT() .. "/" .. name .. ".json"
    end
    handles[path] = setmetatable({
      name = name,
      path = path,
      legacy = legacy,
      _data = nil,
      _mtime = nil,
    }, Handle)
  end
  return handles[path]
end

---The store path for a name, for the few callers that need the file itself.
---@param name string
---@return string
function M.path(name)
  return ROOT() .. "/" .. name .. ".json"
end

return M
