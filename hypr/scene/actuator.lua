-- Turning one intent into compositor calls (LEO-245).
--
-- The only file that dispatches. It exists so the model never has to know
-- which of Hyprland's two very different interfaces a correction needs:
--
--   * the *object* API (`HL.Group:add`/`:remove`) takes the window as an
--     argument and is exact. Grouping goes through it, which is why there is
--     no adjacency search or `moveintogroup` hop chain here any more — those
--     were a workaround for a dispatcher that could only reach the window
--     beside the group;
--   * the *dispatchers*, which act on the focused window. Order and size
--     still need those, so they are a focus-dance: focus, dispatch, hand
--     focus back (LEO-129). The scheduler guarantees the target is on the
--     workspace the user is already looking at, so the dance is invisible and
--     cannot pull them elsewhere.
local M = {}

---@param address string
---@return HL.Window?
local function window(address)
  return hl.get_window("address:" .. address)
end

---@param prev HL.Window?
---@param touched string
local function restore_focus(prev, touched)
  if prev and prev.address and prev.address ~= touched then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. prev.address }))
  end
end

---Run `fn` with `address` focused, then give focus back.
---@param address string
---@param fn fun()
local function focused(address, fn)
  local prev = hl.get_active_window()
  hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
  fn()
  restore_focus(prev, address)
end

---@type table<string, fun(intent: Scene.Intent)>
local ops = {}

function ops.collect(intent)
  -- `follow = false` is the load-bearing half: the plain move takes the user
  -- to the destination workspace, and being moved somewhere you did not ask
  -- to go — on every window that drifted — is indistinguishable from a bug.
  hl.dispatch(hl.dsp.window.move({
    workspace = "name:" .. intent.workspace,
    window = "address:" .. intent.address,
    follow = false,
  }))
end

function ops.join(intent)
  local joiner, target = window(intent.address), window(intent.target)
  if not joiner or not target then
    return
  end
  -- A window can only be added once it is out of whatever group it seeded on
  -- its own; skipping this is how two groups for one block stayed two.
  if joiner.group then
    pcall(function()
      joiner.group:remove(joiner)
    end)
  end
  if target.group then
    pcall(function()
      target.group:add(joiner)
    end)
    return
  end
  -- Neither is grouped yet: make one out of the target, then add the joiner.
  focused(target.address, function()
    hl.dispatch(hl.dsp.group.toggle())
  end)
  local seeded = window(intent.target)
  if seeded and seeded.group then
    pcall(function()
      seeded.group:add(joiner)
    end)
  end
end

function ops.evict(intent)
  local w = window(intent.address)
  if w and w.group then
    pcall(function()
      w.group:remove(w)
    end)
  end
end

function ops.reorder(intent)
  focused(intent.address, function()
    hl.dispatch(hl.dsp.window.move({ direction = intent.dir }))
  end)
end

function ops.resize(intent)
  local w = window(intent.address)
  if not w or not w.size then
    return
  end
  focused(intent.address, function()
    hl.dispatch(hl.dsp.window.resize({ x = intent.width, y = w.size.y }))
  end)
end

---@param intent Scene.Intent
function M.apply(intent)
  local op = ops[intent.op]
  if op then
    op(intent)
  end
end

return M
