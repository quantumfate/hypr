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
function M.new()
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

  function hl.bind(key, action, opts)
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

  return hl
end

return M
