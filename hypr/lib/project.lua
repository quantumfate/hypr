-- Project-bindings resolution (LEO-311 chunk D): pure functions that turn
-- "the window that is focused right now" into "the project window a bind
-- should act on", with no hardcoded project name anywhere. Everything here
-- is resolved against the dynamic class group `,proj.sh` builds
-- (bin/,proj.sh: a project is kitty windows classed `Proj-<name>`, each
-- carrying a launch-time role tag `slot:<role>` — the same tag vocabulary
-- hypr/scene/identify.lua stamps for scene blocks, reused here for a
-- project's own template windows and its declared scopes alike).
--
-- Pure: no `hl` calls in this module. The caller (hypr/binds.lua) reads
-- `hl.get_active_window()` / `hl.get_windows()` and hands the results in,
-- so this is testable with plain tables (tests/project_spec.lua) and
-- drivable live via `hq lua` without a bind ever firing (AGENTS.md: `hq
-- key` cannot fire a Lua bind closure).
local M = {}

M.CLASS_PREFIX = "Proj-"

---The fixed template roles, in the order a project's tabs should sit.
---Mirrors `bin/,proj.sh`'s `TEMPLATE_WINDOWS` the same way `class_for`
---mirrors its `class_for`: both sides agree without either shelling out to
---the other. A project's declared scopes are not here — they are opened on
---demand and have no declared position, so they sort after the template in
---the order they joined.
M.TEMPLATE_ROLES = { "nvim", "yazi", "zsh", "run" }

---The role a `slot:<role>` tag names, or nil for any other tag.
---@param tags string[]?
---@return string?
function M.slot_role(tags)
  for _, tag in ipairs(tags or {}) do
    -- Hyprland renders a tag it applied itself with a trailing `*`; match
    -- the role without it.
    local role = tag:match("^slot:([^*]+)")
    if role then
      return role
    end
  end
  return nil
end

---Where `role` sits in the template, or nil for a scope (anything the
---template does not name).
---@param role string?
---@return integer?
function M.template_index(role)
  if not role then
    return nil
  end
  for i, name in ipairs(M.TEMPLATE_ROLES) do
    if name == role then
      return i
    end
  end
  return nil
end

---Hyprland matches classes as regex, so `,proj.sh`'s `class_for` keeps to
---[A-Za-z0-9_-] — mirrored here so both sides agree on one project's class
---without either shelling out to the other.
---@param name string
---@return string
function M.class_for(name)
  return M.CLASS_PREFIX .. (name:gsub("[^%w_%-]", "_"))
end

---The project name a `Proj-<name>` class names, or nil for any other class
---(a plain window, a scene's own class, an unclassed one).
---@param class string?
---@return string?
function M.project_name_from_class(class)
  if not class or class:sub(1, #M.CLASS_PREFIX) ~= M.CLASS_PREFIX then
    return nil
  end
  local name = class:sub(#M.CLASS_PREFIX + 1)
  return name ~= "" and name or nil
end

---The active project's class, resolved from whatever window is focused
---right now — nil when nothing is focused or the focused window is not a
---project window. This is the one place "which project" gets decided; every
---other function below takes the class it returns, so a hardcoded project
---name never enters the picture.
---@param active_window HL.Window?
---@return string?
function M.focused_class(active_window)
  local class = active_window and active_window.class
  return M.project_name_from_class(class) and class or nil
end

---@param tags string[]?
---@param tag string
---@return boolean
local function has_tag(tags, tag)
  for _, t in ipairs(tags or {}) do
    if t == tag then
      return true
    end
  end
  return false
end

---The address of the live window of `class` carrying `slot:<role>`, or nil
---— "focus nvim" and "focus run" both resolve through this, and a spawned
---scope checks it first to decide focus-vs-spawn. Derived fresh from
---`windows` every call, same "no remembered set" rule the scene side
---(hypr/scene/identify.lua's `taken_slots`) already follows.
---@param windows HL.Window[]
---@param class string
---@param role string
---@return string?
function M.slot_address(windows, class, role)
  local tag = "slot:" .. role
  for _, w in ipairs(windows or {}) do
    if w.class == class and has_tag(w.tags, tag) then
      return w.address
    end
  end
  return nil
end

return M
