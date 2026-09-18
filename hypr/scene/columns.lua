-- Fits a scene's declared column roles into what a monitor can actually
-- give, per docs/columns.md: one resolver owns sizing, folding and
-- alignment; `scene` and `deck` become presentations over whatever it
-- decides (not wired yet -- this chunk is the pure module and its specs).
--
-- Pure: no `hl`, no dispatch, no timers. See docs/columns.md §1-§3 for the
-- contract this implements.
local M = {}

---@class Columns.Role
---@field priority integer 1 = most important; reuses the declaration's
---`order` field (docs/columns.md §1)
---@field min_width number narrowest width the role can present itself in
---@field fixed_width number? an exact width instead of a share of the
---slack -- never shrinks below or grows past this number (§3)
---@field align "left"|"center"|"right"? default "left" (§1)
---@field fold_into integer? another role's `priority` to fold into,
---absent = the next one up once this role cannot keep its own column

---@class Columns.Resolved
---@field priority integer the surviving column's own (leader) priority
---@field width number px
---@field x_offset number px, the row's alignment shift (§3) -- almost
---always 0; nonzero only when every surviving column is fixed-width (or
---exactly one survives) and its leader's `align` claims unclaimed width
---@field members integer[] role priorities folded into this column, self
---included, in the order they joined

---A role's effective width for cost/floor/ceiling purposes: its declared
---`fixed_width`, or its `min_width` when it has none.
---@param role Columns.Role
---@return number
local function effective_width(role)
  return role.fixed_width or role.min_width
end

---Cost of the currently surviving columns: their effective widths plus a
---gap between each pair (§3 step 2).
---@param columns { role: Columns.Role, members: integer[] }[]
---@param gaps_in number
---@return number
local function cost(columns, gaps_in)
  local sum = 0
  for _, c in ipairs(columns) do
    sum = sum + effective_width(c.role)
  end
  return sum + gaps_in * (#columns - 1)
end

---The surviving column carrying `priority`, as its own leader or among its
---already-folded-in members -- a `fold_into` target may itself have folded
---into something else first.
---@param columns { role: Columns.Role, members: integer[] }[]
---@param priority integer
---@return table?
local function column_carrying(columns, priority)
  for _, c in ipairs(columns) do
    if c.role.priority == priority then
      return c
    end
    for _, member in ipairs(c.members) do
      if member == priority then
        return c
      end
    end
  end
  return nil
end

---One step of the folding ladder (§3 step 4): fold the lowest-priority
---surviving column into its target. `columns` stays sorted ascending by
---each column's own leader priority, so the least important survivor is
---always the last entry.
---@param columns { role: Columns.Role, members: integer[] }[]
local function fold_one(columns)
  local victim_index = #columns
  local victim = columns[victim_index]

  local target = victim.role.fold_into and column_carrying(columns, victim.role.fold_into)
  if target == victim then
    -- A mis-declared self-fold falls back to "the next one up", same as no
    -- `fold_into` at all.
    target = nil
  end
  target = target or columns[victim_index - 1]

  for _, member in ipairs(victim.members) do
    target.members[#target.members + 1] = member
  end
  table.remove(columns, victim_index)
end

---Resolve a scene's declared roles into columns, following the folding
---ladder and distribution rules in docs/columns.md §3.
---@param roles Columns.Role[]
---@param available_width number px, the live monitor's tiled span (already
---net of that monitor's resolved `gaps_out` on both sides -- §1)
---@param gaps_in number px, gap between resolved columns
---@param _gaps_out number? px, resolved outer gap -- part of the resolver's
---documented input shape (§1), but not consumed here: `available_width`
---already has it subtracted by the caller before this runs
---@return Columns.Resolved[]
function M.resolve(roles, available_width, gaps_in, _gaps_out)
  gaps_in = gaps_in or 0
  if #roles == 0 then
    -- No roles declared: the whole width is one implicit column, exactly
    -- as an empty `blocks` list already behaves (§2).
    return {}
  end

  local sorted = {}
  for i, role in ipairs(roles) do
    sorted[i] = role
  end
  table.sort(sorted, function(a, b)
    return a.priority < b.priority
  end)

  local columns = {}
  for i, role in ipairs(sorted) do
    columns[i] = { role = role, members = { role.priority } }
  end

  while #columns > 1 and cost(columns, gaps_in) > available_width do
    fold_one(columns)
  end

  local total = cost(columns, gaps_in)
  if total > available_width then
    -- Degenerate case (§3): even the one surviving column is under its own
    -- effective width. Nowhere left to fold to, so it takes the whole of
    -- `available_width` regardless of whether that number was fixed.
    local leader = columns[1]
    return { { priority = leader.role.priority, width = available_width, x_offset = 0, members = leader.members } }
  end

  local slack = available_width - total
  local recipient
  for _, c in ipairs(columns) do
    if not c.role.fixed_width then
      recipient = c
      break
    end
  end

  -- Every surviving column is fixed-width: nothing can grow to claim the
  -- leftover, so the whole row shifts as a block per the highest-priority
  -- surviving column's `align`.
  local row_shift = 0
  if not recipient and slack > 0 then
    local align = columns[1].role.align or "left"
    if align == "right" then
      row_shift = slack
    elseif align == "center" then
      row_shift = slack / 2
    end
  end

  local out = {}
  for i, c in ipairs(columns) do
    local width = effective_width(c.role)
    if c == recipient then
      width = width + slack
    end
    out[i] = { priority = c.role.priority, width = width, x_offset = row_shift, members = c.members }
  end
  return out
end

return M
