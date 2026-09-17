-- Group adapters (LEO-380): decide the order `mod+j/k` walks inside a
-- group. A registry keyed by class (a class is unambiguous group membership
-- — `hypr/scene/grouping.lua` folds only one block's classes per group)
-- picks the adapter; each adapter is `order(members, ctx) -> addresses`.
--
-- Dofus orders by the team roster (`hypr/services/dofus/team.lua`'s store).
-- Everything else falls back to the default adapter: a stable join-order
-- list, kept here and updated by the executor (`hypr/events/scene.lua`) as
-- windows join/leave a group, degrading to `group.members` order (the
-- `members` argument itself) when nothing has been recorded yet.
local common = require("hypr.services.dofus.common")

local M = {}

---@class GroupAdapter
---@field order fun(members: { address: string, title: string? }[], ctx: table?): string[]

-- Per-group join order for the default adapter, keyed by `ctx.group_key`
-- (the group's lowest member address — the same identity
-- `hypr/scene/grouping.lua`'s `group_key` uses). Session-only, like
-- `hypr/scene/order.lua`'s tile-swap override: a reload drops it back to
-- `group.members` order.
local join_order = {}

---Record `address` joining `group_key`'s group, appending it if new.
---@param group_key string
---@param address string
function M.record_join(group_key, address)
  local list = join_order[group_key]
  if not list then
    list = {}
    join_order[group_key] = list
  end
  for _, a in ipairs(list) do
    if a == address then
      return
    end
  end
  list[#list + 1] = address
end

---Forget `address` leaving `group_key`'s group (eject or close).
---@param group_key string
---@param address string
function M.record_leave(group_key, address)
  local list = join_order[group_key]
  if not list then
    return
  end
  for i, a in ipairs(list) do
    if a == address then
      table.remove(list, i)
      return
    end
  end
end

---Drop a group's whole recorded order (it dissolved).
---@param group_key string
function M.forget(group_key)
  join_order[group_key] = nil
end

---Recorded join order, filtered to the members still present and extended
---with any present member that was never recorded (a group seeded before
---this ran, or `group.members` outrunning the record) — degrading to
---`members`' own order when nothing was recorded at all.
---@param members { address: string }[]
---@param group_key string?
---@return string[]
local function default_order(members, ctx)
  local recorded = ctx and ctx.group_key and join_order[ctx.group_key]
  local present = {}
  for _, m in ipairs(members) do
    present[m.address] = true
  end

  local ordered, seen = {}, {}
  for _, address in ipairs(recorded or {}) do
    if present[address] then
      ordered[#ordered + 1] = address
      seen[address] = true
    end
  end
  for _, m in ipairs(members) do
    if not seen[m.address] then
      ordered[#ordered + 1] = m.address
    end
  end
  return ordered
end

---Dofus roster order (`hypr/services/dofus/common.lua`'s `team()`, turn
---order). A member not in the roster (a stray Dofus window opened outside
---the team UI) is appended, sorted by address for determinism.
---@param members { address: string, title: string? }[]
---@return string[]
local function dofus_order(members)
  local by_title, present = {}, {}
  for _, m in ipairs(members) do
    by_title[m.title] = m.address
    present[m.address] = true
  end

  local ordered = {}
  for _, name in ipairs(common.team()) do
    local address = by_title[common.title_prefix .. name]
    if address then
      ordered[#ordered + 1] = address
      present[address] = nil
    end
  end

  local rest = {}
  for address in pairs(present) do
    rest[#rest + 1] = address
  end
  table.sort(rest)
  for _, address in ipairs(rest) do
    ordered[#ordered + 1] = address
  end
  return ordered
end

M.default = { order = default_order }

---Keyed by class rather than scene/block name: a group is one class set
---(`hypr/scene/grouping.lua` never mixes two blocks in one group), so the
---class of any member already picks the right adapter.
M.registry = {
  ["Dofus.x64"] = { order = dofus_order },
}

---The adapter for a member class, or the default.
---@param class string?
---@return GroupAdapter
function M.for_class(class)
  return (class and M.registry[class]) or M.default
end

return M
