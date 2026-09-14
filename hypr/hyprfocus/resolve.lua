-- Fold the base declaration and a mode's deltas into one complete desk.
--
-- This is the load-bearing rule of hyprfocus: **deltas are a writing
-- convenience and have no runtime existence.** Nothing acts on a delta.
-- Everything acts on a resolved desk.
--
-- The reason is not tidiness. If deltas were applied one at a time against a
-- running system, the result would depend on the order they happened to be
-- applied — which is exactly the failure the corrective window engine died of,
-- arriving in a new place. Resolving first makes a mode's meaning a pure
-- function of the declaration, so the same mode always means the same desk.
--
-- Pure: no `hl`, no store, no IO. The compositor, the shell and the CLI each
-- call this with a parsed declaration and get the same answer.
local M = {}

-- Resource kinds whose value is a set of names, and which therefore take the
-- `only` / `add` / `remove` delta grammar. `scenes` is not among them: a scene
-- is admitted with its workspace, and per-mode substitution is not in v1.
local LIST_KINDS = { "workspaces", "bindings", "services", "projects" }

-- A `requires` reference is written singular and qualified (`service:obsidian`)
-- because requirements cross kinds: opening a project pulls in the background
-- work it needs. This maps a reference's kind onto the desk field it lands in.
local REF_KIND = {
  workspace = "workspaces",
  binding = "bindings",
  service = "services",
  project = "projects",
}

-- The same mapping the other way, so a desk field can name itself in a
-- reference without searching for its own singular.
local KIND_REF = {}
for singular, plural in pairs(REF_KIND) do
  KIND_REF[plural] = singular
end

---@alias Hyprfocus.Delta { only: string[]?, add: string[]?, remove: string[]? }

---@class Hyprfocus.Desk
---@field workspaces string[]
---@field bindings string[]
---@field services string[]
---@field projects string[]
---@field scenes table<string, table>
---@field notify table<string, string>
---@field revoke table<string, string>
---@field presentation table
---@field mode string

---@param list string[]?
---@return string[]
local function copy(list)
  local out = {}
  for i, value in ipairs(list or {}) do
    out[i] = value
  end
  return out
end

---Apply one kind's delta to the base's set, preserving declaration order so a
---resolved desk is stable to compare and diff. Added names land at the end, in
---the order the mode wrote them.
---@param base string[]?
---@param delta Hyprfocus.Delta?
---@param where string context for errors
---@return string[]
local function apply(base, delta, where)
  if delta == nil then
    return copy(base)
  end
  if delta.only and (delta.add or delta.remove) then
    error(("%s: `only` cannot be combined with `add` or `remove`"):format(where), 0)
  end
  if delta.only then
    return copy(delta.only)
  end

  local removed = {}
  for _, name in ipairs(delta.remove or {}) do
    removed[name] = true
  end

  local out, seen = {}, {}
  for _, name in ipairs(base or {}) do
    if not removed[name] and not seen[name] then
      out[#out + 1] = name
      seen[name] = true
    end
  end
  for _, name in ipairs(delta.add or {}) do
    if not seen[name] then
      out[#out + 1] = name
      seen[name] = true
    end
  end
  return out
end

---@param base table<string, any>?
---@param overrides table<string, any>?
---@return table<string, any>
local function merge(base, overrides)
  local out = {}
  for key, value in pairs(base or {}) do
    out[key] = value
  end
  for key, value in pairs(overrides or {}) do
    out[key] = value
  end
  return out
end

---Split `service:obsidian` into the desk field and the name.
---@param ref string
---@return string?, string?
local function parse_ref(ref)
  local kind, name = tostring(ref):match("^([a-z]+):(.+)$")
  return REF_KIND[kind or ""], name
end

---Pull in what the admitted resources imply, transitively.
---
---Two strengths, mirroring systemd rather than inventing a vocabulary:
---
---  * `requires` — cannot function without it. A mode that explicitly removes
---    something required is a conflict, reported rather than guessed at.
---  * `wants` — uses it, but runs without it. Pulled in by default; a mode that
---    removes it wins, silently.
---
---`wants` is the common case. Obsidian without its indexer is degraded, not
---broken, which is exactly why a media mode can keep the window and stop the
---indexing to reclaim resources. Modelling that as a hard requirement would
---make a behaviour that already ships impossible to express.
---
---Requirements express COMPOSITION — "Obsidian is a window plus an indexer
---plus a sync timer" — and nothing else. Ordering, readiness and failure
---handling between one capability's units belong in the unit files, where
---systemd already does them properly. A resolver that tried to sequence units
---would be reimplementing `After=` badly.
---
---Declaring the edge once, next to the thing it belongs to, is the point: a
---mode that opens Obsidian should not have to remember its services, and
---every other mode that opens Obsidian should not have to repeat them.
---@param desk Hyprfocus.Desk
---@param base table the base declaration, for its `requires` and `wants` graphs
---@param mode string
---@param removed table<string, table<string, true>> explicit removals, per kind
local function close_requirements(desk, base, mode, removed)
  local requires, wants = base.requires or {}, base.wants or {}
  local present = {}
  for _, kind in ipairs(LIST_KINDS) do
    present[kind] = {}
    for _, name in ipairs(desk[kind]) do
      present[kind][name] = true
    end
  end

  -- Breadth-first over the admitted set. `seen` is keyed by reference, so a
  -- diamond (two projects needing one service) is visited once and a cycle
  -- terminates instead of recursing forever.
  local queue, seen = {}, {}
  for _, kind in ipairs(LIST_KINDS) do
    for _, name in ipairs(desk[kind]) do
      queue[#queue + 1] = KIND_REF[kind] .. ":" .. name
    end
  end

  local head = 1
  while head <= #queue do
    local key = queue[head]
    head = head + 1
    if not seen[key] then
      seen[key] = true
      for strength, graph in pairs({ requires = requires, wants = wants }) do
        for _, ref in ipairs(graph[key] or {}) do
          local kind, name = parse_ref(ref)
          -- assert, not `if not kind then error()`: re-assignment keeps both
          -- narrowed to string for the lookups below.
          local malformed = ("mode '%s': malformed %s reference '%s' on %s"):format(mode, strength, tostring(ref), key)
          kind = assert(kind, malformed)
          name = assert(name, malformed)
          name =
            assert(name, ("mode '%s': malformed %s reference '%s' on %s"):format(mode, strength, tostring(ref), key))
          if removed[kind][name] then
            if strength == "requires" then
              -- `remove` says this should not be here and a hard requirement
              -- says it must be. Reporting beats guessing: adding it ignores
              -- what the mode said, omitting it breaks whatever needed it.
              error(("mode '%s': %s '%s' is removed but required by %s"):format(mode, kind, name, key), 0)
            end
            -- A soft `wants` yields to the mode without comment: dropping a
            -- companion is the whole point of a mode that trims cost.
          elseif not present[kind][name] then
            present[kind][name] = true
            desk[kind][#desk[kind] + 1] = name
            queue[#queue + 1] = ref
          end
        end
      end
    end
  end
end

---Every name a resolved desk refers to must be something the base defines.
---Checking here rather than at reconcile time is deliberate: a typo should
---fail when the declaration is read, naming the mode and the kind, not
---silently resolve to a desk that is quietly missing a workspace.
---@param desk Hyprfocus.Desk
---@param base table
---@param mode string
local function check_known(desk, base, mode)
  for _, kind in ipairs(LIST_KINDS) do
    local known = {}
    for _, name in ipairs(base[kind] or {}) do
      known[name] = true
    end
    for _, name in ipairs(desk[kind]) do
      if not known[name] then
        error(("mode '%s': unknown %s '%s' — not declared in base"):format(mode, kind, name), 0)
      end
    end
  end
end

---Drop scenes whose workspace this mode does not admit, so a resolved desk
---never carries geometry for a workspace that is not there.
---@param desk Hyprfocus.Desk
local function prune_scenes(desk)
  local admitted = {}
  for _, workspace in ipairs(desk.workspaces) do
    admitted[workspace] = true
  end
  local kept = {}
  for workspace, scene in pairs(desk.scenes) do
    if admitted[workspace] then
      kept[workspace] = scene
    end
  end
  desk.scenes = kept
end

---The complete desk a mode means.
---@param declaration table parsed hyprfocus.json
---@param mode string mode id
---@return Hyprfocus.Desk
function M.resolve(declaration, mode)
  assert(type(declaration) == "table", "declaration must be a table")
  local base = declaration.base or {}
  local spec = (declaration.modes or {})[mode]
  if not spec then
    error(("unknown mode '%s'"):format(mode), 0)
  end

  -- Explicit shape, filled wholesale: LuaLS checks a table literal against
  -- its assigned type, so a half-built desk would read as missing fields ten
  -- assignments too early. Every per-kind list and presentation is patched
  -- further down before the desk leaves this function.
  local desk = {
    mode = mode,
    workspaces = {},
    bindings = {},
    services = {},
    projects = {},
    scenes = {},
    notify = {},
    revoke = {},
    presentation = {},
  }
  local removed = {}
  for _, kind in ipairs(LIST_KINDS) do
    desk[kind] = apply(base[kind], spec[kind], ("mode '%s', %s"):format(mode, kind))
    removed[kind] = {}
    -- Only `remove` counts as an explicit refusal. `only` says what to inherit
    -- rather than what to forbid, so the requirement closure may still add to
    -- it — which is what lets a narrow mode still get a working app.
    for _, name in ipairs(spec[kind] and spec[kind].remove or {}) do
      removed[kind][name] = true
    end
  end

  -- Scenes come from the base wholesale; the check below drops any whose
  -- workspace this mode does not admit, so a resolved desk never describes
  -- geometry for a workspace that is not there.
  desk.scenes = merge(base.scenes, nil)
  desk.notify = merge(base.notify, spec.notify)
  desk.revoke = merge(base.revoke, spec.revoke)
  desk.presentation = merge(spec.presentation, nil)

  close_requirements(desk, base, mode, removed)
  check_known(desk, base, mode)
  prune_scenes(desk)
  return desk
end

---Resolve every declared mode, so a malformed one fails at load rather than at
---the moment it is entered.
---@param declaration table
---@return table<string, Hyprfocus.Desk>
function M.resolve_all(declaration)
  local out = {}
  for mode in pairs(declaration.modes or {}) do
    out[mode] = M.resolve(declaration, mode)
  end
  return out
end

---How a resource is given up when a mode stops admitting it. Windows default
---to `hold` (their state lives in them and the cost of keeping them is low);
---everything else defaults to `retire` (the cost is the reason it is being
---revoked, so holding buys nothing).
---@param desk Hyprfocus.Desk
---@param kind string
---@param name string
---@return "hold"|"retire"
function M.revocation(desk, kind, name)
  local declared = desk.revoke and desk.revoke[name]
  if declared then
    return declared
  end
  if kind == "workspaces" or kind == "projects" then
    return "hold"
  end
  return "retire"
end

return M
