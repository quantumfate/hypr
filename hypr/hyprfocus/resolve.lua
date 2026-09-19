-- Fold the base declaration and a mode into one complete desk.
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
-- A mode names its scene SET outright (`scenes: [{name, monitor}]`); the
-- workspaces it admits are derived from that set. Before resolving, `validate`
-- refuses a mode whose set is malformed — see docs/scenes.md "Scene sets".
--
-- Pure: no `hl`, no store, no IO. The compositor, the shell and the CLI each
-- call this with a parsed declaration and get the same answer. The Python
-- twin in bin/,hyprfocus moves in lockstep (tests/fixtures/hyprfocus/resolver).
local M = {}

-- Resource kinds whose value is a set of names, and which therefore take the
-- `only` / `add` / `remove` delta grammar. Scenes are not among them: a mode
-- lists its scene set explicitly.
local LIST_KINDS = { "bindings", "services", "projects" }

-- A `requires` reference is written singular and qualified (`service:obsidian`)
-- because requirements cross kinds. This maps a reference's kind onto the desk
-- field it lands in. `scene` refs are checked against the mode's set, never
-- added to it.
local REF_KIND = {
  scene = "scenes",
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

--- Host monitor roles a placement may name (conf/hosts/*.lua).
M.MONITOR_ROLES = { primary = true, secondary = true }

---@alias Hyprfocus.Delta { only: string[]?, add: string[]?, remove: string[]? }

---@class Hyprfocus.Placement
---@field name string scene name (also its workspace name)
---@field monitor "primary"|"secondary" host monitor role

---@class Hyprfocus.Refusal
---@field stage "admit"
---@field event "mode_refused"
---@field decision "refuse"
---@field mode string
---@field refusal string token, e.g. unknown_scene, class_conflict (docs/scenes.md "Scene sets")
---@field reason string token-first readable message
---@field class string? the contested claim, for class_conflict
---@field scenes string[]? the scenes involved

---@class Hyprfocus.Desk
---@field mode string
---@field hidden boolean
---@field main string? the scene this mode calls home (LEO-400); one of this
---mode's own `scenes`, or nil for a declaration that predates it
---@field scenes Hyprfocus.Placement[] the active set, declaration order
---@field scene_specs table<string, table> catalog entries of the active set
---@field workspaces string[] derived: the active set's names
---@field bindings string[]
---@field services string[]
---@field projects string[]
---@field notify table<string, string>
---@field revoke table<string, string>
---@field presentation table

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

---Build a refusal record: token first in `reason`, so an error raised from it
---matches fixtures by substring.
---@param mode string
---@param token string
---@param detail string
---@param extra table? class / scenes
---@return Hyprfocus.Refusal
local function refusal(mode, token, detail, extra)
  local record = {
    stage = "admit",
    event = "mode_refused",
    decision = "refuse",
    mode = mode,
    refusal = token,
    reason = ("%s: mode '%s': %s"):format(token, mode, detail),
  }
  for key, value in pairs(extra or {}) do
    record[key] = value
  end
  return record
end

---Check a mode's scene set before anything resolves it. Pure; returns the
---first refusal, or nil when the mode is admissible. The whole mode is refused
---on any failure — nothing is partially applied.
---
---Claims are the strings in each block's `classes`, compared textually: two
---regexes that happen to overlap are not detected. `barred` and `spawn.class`
---are not claims.
---@param declaration table
---@param mode string
---@return Hyprfocus.Refusal?
function M.validate(declaration, mode)
  local spec = ((declaration or {}).modes or {})[mode]
  if not spec then
    return refusal(mode, "unknown_mode", "not declared")
  end
  if type(spec.scenes) ~= "table" then
    return refusal(mode, "missing_scenes", "no `scenes` list (a pre-v3 declaration?)")
  end
  if mode == "neutral" and spec.hidden ~= true then
    return refusal(mode, "hidden_required", "neutral is the recovery fallback and must be hidden")
  end

  local catalog = ((declaration.base or {}).scenes or {})
  local drawers = ((declaration.base or {}).drawers or {})

  -- Drawer keys are checked once per call, independent of the mode: one key
  -- per drawer everywhere (LEO-363), so two catalog entries sharing a key is
  -- a declaration error before any scene set is even considered — the same
  -- footing as a class two active scenes both claim.
  local drawer_key_owner = {}
  for id, drawer in pairs(drawers) do
    local key = drawer.key
    local owner = drawer_key_owner[key]
    if owner and owner ~= id then
      return refusal(
        mode,
        "drawer_key_conflict",
        ("drawer key '%s' claimed by %s and %s"):format(tostring(key), owner, id),
        { key = key, drawers = { owner, id } }
      )
    end
    drawer_key_owner[key] = id
  end

  local listed = {}
  local claimed_by = {}
  for _, placement in ipairs(spec.scenes) do
    local name = placement.name
    if catalog[name] == nil then
      return refusal(mode, "unknown_scene", ("scene '%s' is not in base.scenes"):format(tostring(name)))
    end
    if not M.MONITOR_ROLES[placement.monitor] then
      return refusal(
        mode,
        "unknown_monitor",
        ("scene '%s' names monitor '%s', not a host role"):format(name, tostring(placement.monitor)),
        { scenes = { name } }
      )
    end
    if listed[name] then
      return refusal(mode, "duplicate_scene", ("scene '%s' is listed twice"):format(name), { scenes = { name } })
    end
    listed[name] = true

    for _, drawer_id in ipairs(catalog[name].drawers or {}) do
      if drawers[drawer_id] == nil then
        return refusal(
          mode,
          "unknown_drawer",
          ("scene '%s' assigns unknown drawer '%s'"):format(name, tostring(drawer_id)),
          { scenes = { name } }
        )
      end
    end

    for _, block in ipairs(catalog[name].blocks or {}) do
      for _, class in ipairs(block.classes or {}) do
        -- A slot-bearing block (LEO-364) claims the launch-identity tag, not
        -- the bare class, so it keys separately: two scenes sharing a class
        -- (pokemon and dofus, both `zen-gaming-media`) stay unflagged once a
        -- slot disambiguates one side.
        local key = block.slot and (class .. ":" .. block.slot) or class
        local owner = claimed_by[key]
        if owner and owner ~= name then
          return refusal(
            mode,
            "class_conflict",
            ("class '%s' claimed by %s and %s"):format(class, owner, name),
            { class = class, scenes = { owner, name } }
          )
        end
        claimed_by[key] = name
      end
    end
  end

  -- `main` (LEO-400) names the scene this mode calls home -- the fallback a
  -- reload restore or a fresh mode entry lands on. Optional for now (a
  -- pre-LEO-400 declaration has none), but when present it must be one of
  -- THIS mode's own admitted scenes: naming one the mode does not list would
  -- make the fallback itself unreachable.
  if spec.main ~= nil and not listed[spec.main] then
    return refusal(mode, "unknown_main", ("main '%s' is not one of this mode's own scenes"):format(tostring(spec.main)))
  end
  return nil
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
---A `scene:` reference is only CHECKED: a required scene missing from the
---mode's set refuses the mode, a wanted one is ignored. Scene sets are
---explicit, so closure never adds a scene.
---
---Requirements express COMPOSITION — "Obsidian is a window plus an indexer
---plus a sync timer" — and nothing else. Ordering, readiness and failure
---handling between one capability's units belong in the unit files.
---@param desk Hyprfocus.Desk
---@param base table the base declaration, for its `requires` and `wants` graphs
---@param mode string
---@param removed table<string, table<string, true>> explicit removals, per kind
local function close_requirements(desk, base, mode, removed)
  local requires, wants = base.requires or {}, base.wants or {}
  local present = { scenes = {} }
  for _, name in ipairs(desk.workspaces) do
    present.scenes[name] = true
  end
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
  for _, name in ipairs(desk.workspaces) do
    queue[#queue + 1] = "scene:" .. name
  end
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
          local malformed = ("mode '%s': malformed %s reference '%s' on %s"):format(mode, strength, tostring(ref), key)
          kind = assert(kind, malformed)
          name = assert(name, malformed)
          if kind == "scenes" then
            if strength == "requires" and not present.scenes[name] then
              error(
                ("scene_required: mode '%s': scene '%s' is required by %s but not in the mode's scene set"):format(
                  mode,
                  name,
                  key
                ),
                0
              )
            end
          elseif removed[kind][name] then
            if strength == "requires" then
              error(("mode '%s': %s '%s' is removed but required by %s"):format(mode, kind, name, key), 0)
            end
            -- A soft `wants` yields to the mode without comment.
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

---The complete desk a mode means. Raises on a refused or unresolvable mode;
---a refusal's message starts with its token.
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
  local refused = M.validate(declaration, mode)
  if refused then
    error(refused.reason, 0)
  end

  local desk = {
    mode = mode,
    hidden = spec.hidden == true,
    main = spec.main,
    scenes = {},
    scene_specs = {},
    workspaces = {},
    bindings = {},
    services = {},
    projects = {},
    notify = {},
    revoke = {},
    presentation = {},
  }
  for i, placement in ipairs(spec.scenes) do
    desk.scenes[i] = { name = placement.name, monitor = placement.monitor }
    desk.scene_specs[placement.name] = base.scenes[placement.name]
    desk.workspaces[i] = placement.name
  end

  local removed = {}
  for _, kind in ipairs(LIST_KINDS) do
    desk[kind] = apply(base[kind], spec[kind], ("mode '%s', %s"):format(mode, kind))
    removed[kind] = {}
    -- Only `remove` counts as an explicit refusal. `only` says what to inherit
    -- rather than what to forbid, so the requirement closure may still add to it.
    for _, name in ipairs(spec[kind] and spec[kind].remove or {}) do
      removed[kind][name] = true
    end
  end

  desk.notify = merge(base.notify, spec.notify)
  desk.revoke = merge(base.revoke, spec.revoke)
  desk.presentation = merge(spec.presentation, nil)

  close_requirements(desk, base, mode, removed)
  check_known(desk, base, mode)
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
---everything else defaults to `retire`.
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
