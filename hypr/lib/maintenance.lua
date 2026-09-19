-- Session-start maintenance: seed what is missing, reseed what is stale.
--
-- Seeding and syncing used to be commands a person had to remember to run
-- (`,hyprfocus seed`, `,proj.sh sync`). This module runs them automatically,
-- once, when `hyprland.start` fires (`hypr/events/start.lua`), and logs each
-- action through `hypr/lib/trace.lua` with `stage = "maintenance"` so the
-- work is visible without having asked for it by hand.
--
-- Cheap by construction: every check below reads a small file (no
-- subprocess) and only shells out when something is actually missing or
-- older than what is shipped, so a normal login with nothing to do costs one
-- stat and zero log lines.
local store = require("hypr.lib.store")
local trace = require("hypr.lib.trace")
local json = require("hypr.lib.json")

local M = {}

---Path to the shipped hyprfocus declaration in the sibling quickshell repo,
---resolved from this file's own location -- the same convention
---tests/hyprfocus_test.sh and tests/hyprfocus_declaration_spec.lua already
---use. A field (not a local) so a spec can point it at a scratch tree.
---@return string
function M.shipped_declaration_path()
  local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/")
  return here .. "/../../../quickshell/assets/hyprfocus.default.json"
end

---@param path string
---@return table? decoded JSON, or nil if the file is missing/unreadable
local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local raw = f:read("*a")
  f:close()
  local ok, decoded = pcall(json.decode, raw)
  return ok and type(decoded) == "table" and decoded or nil
end

---@param cmd string
---@return boolean ok
local function run(cmd)
  local ok = os.execute(cmd .. " >/dev/null 2>&1")
  -- Lua 5.1 returns a numeric exit code, 5.3+ a boolean; normalize both.
  return ok == true or ok == 0
end

---Seed (or reseed) the hyprfocus declaration from the shipped quickshell
---asset when the store has no declaration yet, or one older than what ships.
---Never writes content of its own -- it only decides WHETHER to invoke the
---same `,hyprfocus seed <file>` a person would type by hand.
local function maintain_hyprfocus()
  local shipped_path = M.shipped_declaration_path()
  local shipped = read_json(shipped_path)
  if not shipped then
    return -- no sibling quickshell checkout to seed from this session
  end

  local current = store.define("hyprfocus"):get()
  local current_version = type(current) == "table" and current.version or nil
  if current_version and current_version >= (shipped.version or 0) then
    return -- already at or ahead of the shipped version: nothing to do
  end

  local ok = run((",hyprfocus seed %q"):format(shipped_path))
  trace.emit({
    stage = "maintenance",
    event = "hyprfocus_seed",
    decision = ok and "seeded" or "failed",
    reason = current_version and ("stale v" .. tostring(current_version)) or "missing",
  })
end

---Populate `projects.json` on the very first run, so `,proj.sh pick`/`open`
---have something to read without a manual `sync` first. Only fires when the
---store is entirely missing -- re-running `sync` on every login would fight
---a user who deliberately edited or pruned an entry.
local function maintain_projects()
  local handle = store.define("projects")
  if handle:get("projects") ~= nil then
    return -- already populated (or deliberately emptied): leave it alone
  end
  local ok = run(",proj.sh sync")
  trace.emit({
    stage = "maintenance",
    event = "projects_sync",
    decision = ok and "synced" or "failed",
    reason = "missing",
  })
end

---Run every maintenance check. Each is independently guarded (pcall), so one
---failing check never blocks the others or the boot it runs ahead of.
function M.run()
  for _, check in ipairs({ maintain_hyprfocus, maintain_projects }) do
    pcall(check)
  end
end

return M
