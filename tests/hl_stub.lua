--- Stub for the `hl` global the Hyprland Lua runtime injects. Outside
--- Hyprland nothing provides it, so specs assign `_G.hl = require("tests.hl_stub").new()`
--- before requiring any hypr.lib module.
---
--- Records what was dispatched instead of swallowing it, so specs can assert
--- on the built bind table (submap, key, description) rather than trusting
--- that construction merely "didn't error".
local M = {}

--- hl.dsp.* / hl.dsp.window.* / hl.dsp.workspace.* are an arbitrarily nested
--- namespace of dispatcher constructors in the real API. A recursive proxy
--- means the stub never needs updating when the config calls a new one.
---@param path string dotted path so far, for the recorded dispatcher's `name`
local function dispatcher_proxy(path)
  return setmetatable({}, {
    __index = function(_, key)
      return dispatcher_proxy(path .. "." .. key)
    end,
    __call = function(_, ...)
      return { __dispatcher = true, name = path, args = { ... } }
    end,
  })
end

--- New stub `hl`. Each spec gets its own so binds/dispatches from one spec
--- never leak into the next.
---@param stub_opts { readonly: boolean? }? `readonly` refuses assignment to
--- `hl` the way the runtime does; for specs that load a real config.
function M.new(stub_opts)
  local hl = {}

  hl.binds = {} ---@type { submap: string, key: string, action: any, opts: table }[]
  hl.dispatched = {}
  hl.exec_cmds = {}
  hl.window_rules = {}
  hl.workspace_rules = {}
  hl.timers = {}
  hl.event_handlers = {}

  -- Submap nesting during config evaluation: hl.define_submap's callback runs
  -- immediately (that's how the real API registers a submap's binds), so a
  -- stack — not just a top name — lets nested submap.tree groups attribute
  -- binds to the right submap.
  local submap_stack = { "" }

  hl.dsp = dispatcher_proxy("dsp")

  -- Registered layout providers, by name. Specs drive `recalculate` directly
  -- with a context they build, the way the compositor would.
  hl.layouts = {}
  hl.layout = {
    register = function(name, provider)
      hl.layouts[name] = provider
    end,
  }

  -- Live config values a module may read (gaps, layout options). Specs set
  -- `hl.config_values` rather than stubbing the getter each time.
  hl.config_values = {}
  function hl.get_config(key)
    return hl.config_values[key]
  end

  --- Reject a key string Hyprland would reject.
  ---
  --- Without this the stub accepts anything and the config-smoke spec is
  --- theatre: the real runtime raises on an unparseable bind and takes down
  --- every module required after it, so a permissive stub means the suite
  --- passes on a config that cannot start a desk.
  ---
  --- Deliberately narrow. It checks that a key is actually named, not that the
  --- name is a real keysym — the stub cannot know the keymap, and guessing
  --- would reject valid binds.
  ---@param key string
  local function validate_key(key)
    if type(key) ~= "string" or key == "" then
      error("hl.bind: failed to create bind: missing key", 0)
    end
    -- Modifiers are "+"-delimited and the list may close with a trailing "+"
    -- ("+SUPER+d+"), so drop that before taking the last segment as the key.
    local trimmed = key:gsub("%+%s*$", "")
    local named = trimmed:match("([^%+]*)$") or ""
    named = named:gsub("^%s+", ""):gsub("%s+$", "")
    if named == "" then
      error(("hl.bind: failed to create bind: no key in %q"):format(key), 0)
    end
    -- A comma inside the key is the shape of a modifier list joined to its key
    -- with ", " instead of nesting the key in the list. Hyprland reports it as
    -- an unknown key.
    if named:find(",") then
      error(("hl.bind: failed to create bind: Unknown key: %s"):format(named), 0)
    end
  end

  function hl.bind(key, action, opts)
    validate_key(key)
    hl.binds[#hl.binds + 1] = {
      submap = submap_stack[#submap_stack],
      key = key,
      action = action,
      opts = opts or {},
    }
  end

  function hl.unbind(key)
    hl.binds[#hl.binds + 1] = { submap = submap_stack[#submap_stack], key = key, unbind = true }
  end

  function hl.define_submap(name, fn)
    submap_stack[#submap_stack + 1] = name
    fn()
    submap_stack[#submap_stack] = nil
  end

  function hl.dispatch(action)
    hl.dispatched[#hl.dispatched + 1] = action
  end

  function hl.exec_cmd(cmd)
    hl.exec_cmds[#hl.exec_cmds + 1] = cmd
  end

  function hl.on(event, cb)
    hl.event_handlers[event] = hl.event_handlers[event] or {}
    table.insert(hl.event_handlers[event], cb)
  end

  function hl.timer(cb, opts)
    local handle = { cb = cb, opts = opts }
    function handle:set_enabled(v)
      self.enabled = v
    end
    function handle:set_timeout(ms)
      self.opts.timeout = ms
    end
    hl.timers[#hl.timers + 1] = handle
    return handle
  end

  function hl.get_current_submap()
    return submap_stack[#submap_stack]
  end

  function hl.get_workspaces()
    return {}
  end
  function hl.get_active_workspace()
    return nil
  end
  function hl.get_active_special_workspace()
    return nil
  end
  function hl.get_windows()
    return {}
  end
  function hl.get_active_window()
    return nil
  end

  -- Specs assign hl.monitors directly to fingerprint against, the same way
  -- they stub other hl.get_* calls by overwriting the field.
  hl.monitors = {}
  function hl.get_monitors()
    return hl.monitors
  end

  -- Rule constructors return a handle carrying `set_enabled`, the way the real
  -- API does: a mode admits and withholds resources through those handles, so
  -- a stub that returned nothing would make that untestable.
  local function rule_handle(spec)
    local handle = { spec = spec, enabled = true }
    function handle:set_enabled(value)
      self.enabled = value
    end
    function handle:is_enabled()
      return self.enabled
    end
    return handle
  end

  function hl.window_rule(spec)
    local handle = rule_handle(spec)
    hl.window_rules[#hl.window_rules + 1] = spec
    return handle
  end
  function hl.workspace_rule(spec)
    local handle = rule_handle(spec)
    hl.workspace_rules[#hl.workspace_rules + 1] = spec
    return handle
  end
  function hl.config(spec)
    hl.last_config = spec
  end

  -- The rest of the runtime surface, recorded rather than implemented. The
  -- config calls these at load, so a stub missing one fails the whole tree —
  -- which is the point: the smoke spec loads the real config through here, and
  -- a module-level error is the failure that takes a desk down with no binds
  -- and no workspace rules.
  hl.calls = {}
  for _, name in ipairs({
    "animation",
    "curve",
    "device",
    "env",
    "gesture",
    "layer_rule",
    "monitor",
    "permission",
  }) do
    hl[name] = function(spec)
      hl.calls[name] = hl.calls[name] or {}
      table.insert(hl.calls[name], spec)
      return {
        set_enabled = function() end,
        is_enabled = function()
          return true
        end,
      }
    end
  end

  hl.notification = {
    create = function()
      return { close = function() end }
    end,
    get = function()
      return {}
    end,
  }
  hl.plugin = { load = function() end }

  function hl.version()
    return "0.0.0-stub"
  end
  function hl.get_cursor_pos()
    return { x = 0, y = 0 }
  end
  function hl.get_workspace()
    return nil
  end
  function hl.get_workspace_windows()
    return {}
  end
  -- Real Hyprland accepts "address:<addr>" as a window selector; specs that
  -- want it resolved through their own `get_windows` override can keep using
  -- that default, so grouping specs need not stub `get_window` separately.
  function hl.get_window(query)
    local address = type(query) == "string" and query:match("^address:(.+)$")
    if not address then
      return nil
    end
    for _, w in ipairs(hl.get_windows() or {}) do
      if w.address == address then
        return w
      end
    end
    return nil
  end
  function hl.get_layers()
    return {}
  end
  function hl.get_active_monitor()
    return nil
  end
  function hl.get_last_window()
    return nil
  end

  -- The runtime's `hl` is read-only: assigning to it raises at config load and
  -- takes down every module required after, which is how that failure reached
  -- a desk twice. Enforcing it is opt-in because every other spec stubs `hl`
  -- methods deliberately — only the spec that simulates a real config load
  -- wants the runtime's own strictness.
  if stub_opts and stub_opts.readonly then
    return setmetatable({}, {
      __index = hl,
      __newindex = function(_, key)
        error(("hl.%s is read-only"):format(tostring(key)), 2)
      end,
    })
  end
  return hl
end

--- A minimal live-shaped `HL.Group`: `.members` (each `{address=...}`, the
--- shape `hypr/scene/grouping.lua`'s `group_key` and `hypr/scene/provider.lua`'s
--- `window_tile` both read) plus `:add`/`:remove`, mutating both the group
--- and the member windows' `.group` field the way the real object does.
--- `windows[address].group = group` seeds membership; grouping specs build
--- one of these per group.toggle to simulate the spike's synchronous result
--- (`hl.get_window(addr).group` non-nil right after the dispatch).
---@param seed HL.Window[] windows already in the group when it is created
function M.new_group(seed)
  local group = { members = {} }
  for _, w in ipairs(seed) do
    group.members[#group.members + 1] = { address = w.address }
    w.group = group
  end
  -- `index` mirrors Hyprland's `HL.Group:add` (1-based insertion position,
  -- default: append) so a spec can assert physical member order, not just
  -- membership.
  function group:add(w, index)
    table.insert(self.members, index or (#self.members + 1), { address = w.address })
    w.group = self
  end
  function group:remove(w)
    for i, member in ipairs(self.members) do
      if member.address == w.address then
        table.remove(self.members, i)
        break
      end
    end
    w.group = nil
  end
  return group
end

return M
