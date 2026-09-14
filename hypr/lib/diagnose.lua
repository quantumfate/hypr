--- Window-placement diagnosis (LEO-213). Explains, for every open window,
--- which window rules it matches, what workspace those rules claim, and where
--- the window actually landed — so a "wrong workspace" report can be chased
--- without guessing.
---
--- Hyprland matches rules against window CLASS at map time, and `initial_class`
--- is the class the client had when it started. Apps that map with a generic
--- class and only switch to a real one later (Electron, most) never see rules
--- keyed on `initial_class`; the report surfaces this by printing both class
--- and initialClass and flagging a note when they differ.
---
--- The matcher is a deliberate PCRE2 subset (the config's rules use alternation
--- groups, `^`/`$`, char classes, `\d`, `.` and `* + ?`): faithful for those
--- constructs, and anything exotic is a literal that just won't match.
local M = {}

---@type table[] every window-rule spec passed through `attach` (or `record`)
M.rules = {}

---@param spec table
function M.record(spec)
  M.rules[#M.rules + 1] = spec
end

--- Intercept `hl.window_rule` so every registered rule is also recorded for
--- the diagnosis. Must run before the config registers its rules.
function M.attach()
  local real = hl.window_rule
  rawset(hl, "window_rule", function(spec)
    M.record(spec)
    real(spec)
  end)
end

-- ---- PCRE2-subset matcher (unchanged: unanchored first match, like Hyprland)

-- Forward declaration; the annotations below belong to the assignment at the
-- bottom of the matcher and to match_one, which share the seq/s/pos contract.
local match_seq

---@param piece table
---@param s string
---@param pos integer 1-based position of the next character to consume
---@return integer? end position (1 past the consumed char) or nil
local function match_one(piece, s, pos)
  if piece.kind == "caret" then
    return pos == 1 and pos or nil
  elseif piece.kind == "dollar" then
    return pos == #s + 1 and pos or nil
  elseif piece.kind == "any" then
    if pos > #s then
      return nil
    end
    local c = s:sub(pos, pos)
    return c ~= "\n" and pos + 1 or nil
  elseif piece.kind == "char" then
    if pos > #s then
      return nil
    end
    return s:sub(pos, pos) == piece.c and pos + 1 or nil
  elseif piece.kind == "class" then
    if pos > #s then
      return nil
    end
    local c = s:sub(pos, pos)
    local inside = piece.chars:find(c, 1, true) ~= nil
    return (piece.neg and not inside or not piece.neg and inside) and pos + 1 or nil
  elseif piece.kind == "group" then
    for _, seq in ipairs(piece.value) do
      local e = match_seq(seq, s, pos)
      if e then
        return e
      end
    end
    return nil
  end
  error("unknown piece kind: " .. piece.kind)
end

--- Greedy `*`/`+`: consume as much as possible, record each reachable position,
--- then retry the rest of the sequence from longest to shortest.
---@param seq table[]
---@param s string
---@param pos integer
---@param si integer index of the quantified element in seq
---@param piece table
---@param min integer
---@return integer?
local function match_star(seq, s, pos, si, piece, min)
  local ends, p, count = {}, pos, 0
  while true do
    if count >= min then
      ends[#ends + 1] = p
    end
    local e = match_one(piece, s, p)
    if not e or e == p then
      break
    end
    p, count = e, count + 1
  end
  for k = #ends, 1, -1 do
    local r = match_seq(seq, s, ends[k], si + 1)
    if r then
      return r
    end
  end
  return nil
end

---@param seq table[]
---@param s string
---@param pos integer
---@param si integer? element index (default 1)
---@return integer?
match_seq = function(seq, s, pos, si)
  if not si then
    si = 1
  end
  if si > #seq then
    return pos
  end
  local piece = seq[si]
  if piece.quant == "?" then
    local e = match_one(piece, s, pos)
    if e and match_seq(seq, s, e, si + 1) then
      return match_seq(seq, s, e, si + 1)
    end
    return match_seq(seq, s, pos, si + 1)
  elseif piece.quant == "*" then
    return match_star(seq, s, pos, si, piece, 0)
  elseif piece.quant == "+" then
    return match_star(seq, s, pos, si, piece, 1)
  else
    local e = match_one(piece, s, pos)
    if e then
      return match_seq(seq, s, e, si + 1)
    end
    return nil
  end
end

---@param alts table[]
---@param s string
---@param pos integer
---@return integer?
local function match_alt(alts, s, pos)
  for _, seq in ipairs(alts) do
    local e = match_seq(seq, s, pos)
    if e then
      return e
    end
  end
  return nil
end

local ESC_LITERALS = {
  ["\\"] = "\\",
  ["."] = ".",
  ["+"] = "+",
  ["*"] = "*",
  ["?"] = "?",
  ["("] = "(",
  [")"] = ")",
  ["["] = "[",
  ["]"] = "]",
  ["^"] = "^",
  ["$"] = "$",
  ["|"] = "|",
  ["-"] = "-",
}
---@param text string
---@param i integer index of the backslash
---@return string, any, integer kind ("char"|"class"), data, next index
local function parse_escape(text, i)
  local e = text:sub(i + 1, i + 1)
  if ESC_LITERALS[e] then
    return "char", ESC_LITERALS[e], i + 2
  end
  if e == "d" then
    return "class", "0123456789", i + 2
  end
  if e == "s" then
    return "class", " \t\n", i + 2
  end
  if e == "t" then
    return "char", "\t", i + 2
  end
  if e == "n" then
    return "char", "\n", i + 2
  end
  return "char", e, i + 2
end

---@param text string
---@param i integer index of the `[`
---@return boolean, string, integer negated?, chars, next index
local function parse_class(text, i)
  local j, neg = i + 1, false
  if text:sub(j, j) == "^" then
    neg, j = true, j + 1
  end
  local chars = ""
  while j <= #text do
    local c = text:sub(j, j)
    if c == "]" then
      return neg, chars, j + 1
    elseif c == "\\" then
      local _, data, nextj = parse_escape(text, j)
      chars = chars .. data
      j = nextj
    else
      chars = chars .. c
      j = j + 1
    end
  end
  error("unterminated character class in rule pattern")
end

---@param text string
---@param i integer
---@return table[] alternatives, integer next index
local function parse_alt(text, i)
  local alts, seq = {}, {}
  local function flush()
    alts[#alts + 1] = seq
    seq = {}
  end
  while i <= #text do
    local c = text:sub(i, i)
    if c == ")" then
      flush()
      return alts, i + 1
    elseif c == "|" then
      flush()
      i = i + 1
    elseif c == "(" then
      local subalts, nexti = parse_alt(text, i + 1)
      seq[#seq + 1] = { kind = "group", value = subalts }
      i = nexti
    elseif c == "[" then
      local neg, chars, nexti = parse_class(text, i)
      seq[#seq + 1] = { kind = "class", neg = neg, chars = chars }
      i = nexti
    elseif c == "*" or c == "+" or c == "?" then
      local p = seq[#seq]
      if not p then
        error("dangling quantifier '" .. c .. "' in rule pattern")
      end
      p.quant = c
      i = i + 1
    elseif c == "." then
      seq[#seq + 1] = { kind = "any" }
      i = i + 1
    elseif c == "^" then
      seq[#seq + 1] = { kind = "caret" }
      i = i + 1
    elseif c == "$" then
      seq[#seq + 1] = { kind = "dollar" }
      i = i + 1
    elseif c == "\\" then
      local kind, data, nexti = parse_escape(text, i)
      if kind == "class" then
        seq[#seq + 1] = { kind = "class", neg = false, chars = data }
      else
        seq[#seq + 1] = { kind = "char", c = data }
      end
      i = nexti
    else
      seq[#seq + 1] = { kind = "char", c = c }
      i = i + 1
    end
  end
  flush()
  return alts, i
end

---Unanchored first-match search, matching Hyprland's regex semantics.
---@param pattern string
---@param s string
---@return boolean
function M.match(pattern, s)
  local alts = parse_alt(pattern, 1)
  for pos = 1, #s + 1 do
    if match_alt(alts, s, pos) then
      return true
    end
  end
  return false
end

-- ---- rule evaluation ------------------------------------------------------

---@param window table
---@param tag string
---@return boolean
local function window_has_tag(window, tag)
  local tags = window.tags
  if tags == nil then
    return false
  end
  if type(tags) == "table" then
    for _, t in ipairs(tags) do
      if t == tag or t == ("+" .. tag) then
        return true
      end
    end
    return false
  end
  return tags == tag or tags == ("+" .. tag)
end

---Does `spec` (a `hl.window_rule` match block) claim `window`?
---@param spec table
---@param window table a window: class/initial_class/title/initial_title/tags/xwayland
---@return boolean
function M.matches(spec, window)
  local m = spec.match
  if not m then
    return false
  end
  if m.initial_class and not M.match(m.initial_class, window.initial_class or "") then
    return false
  end
  if m.class and not M.match(m.class, window.class or "") then
    return false
  end
  if m.initial_title and not M.match(m.initial_title, window.initial_title or "") then
    return false
  end
  if m.title and not M.match(m.title, window.title or "") then
    return false
  end
  if m.tag and not window_has_tag(window, m.tag) then
    return false
  end
  if m.xwayland ~= nil and window.xwayland ~= m.xwayland then
    return false
  end
  return true
end

-- ---- report ---------------------------------------------------------------

---@param effect any rule `workspace` value (`"name:code"`, `"special:comms"`, number)
---@return string
local function describe_workspace(effect)
  if type(effect) == "number" then
    return "workspace " .. tostring(effect)
  end
  return tostring(effect)
end

---@param claimed any
---@param actual table? window.workspace ({ id, name })
---@return boolean
local function workspace_matches_claim(claimed, actual)
  if actual == nil then
    return false
  end
  if type(claimed) == "number" then
    return actual.id ~= nil and actual.id == claimed
  end
  if type(claimed) ~= "string" then
    return false
  end
  if actual.name then
    if claimed == ("name:" .. actual.name) or claimed == ("special:" .. actual.name) then
      return true
    end
    if claimed == actual.name then
      return true
    end
  end
  if actual.id ~= nil and claimed == tostring(actual.id) then
    return true
  end
  return false
end

---Which match fields of `spec.match` hit `window` (for the "via …" column).
---@param spec table
---@param window table
---@return string
local function hit_fields(spec, window)
  local m = spec.match or {}
  local via = {}
  if m.initial_class and M.match(m.initial_class, window.initial_class or "") then
    via[#via + 1] = "initialClass"
  end
  if m.class and M.match(m.class, window.class or "") then
    via[#via + 1] = "class"
  end
  if m.initial_title and M.match(m.initial_title, window.initial_title or "") then
    via[#via + 1] = "initialTitle"
  end
  if m.title and M.match(m.title, window.title or "") then
    via[#via + 1] = "title"
  end
  if m.tag and window_has_tag(window, m.tag) then
    via[#via + 1] = "tag:" .. m.tag
  end
  return table.concat(via, ", ")
end

---Build the diagnosis text.
---@param windows table[] window objects ({ class, initial_class, title,
---   initial_title, tags, workspace={ id, name }, xwayland })
---@param rules table[] rule specs
---@return string
function M.report(windows, rules)
  local lines = {}
  local mismatches = 0
  for i, w in ipairs(windows) do
    local matched = {}
    for _, spec in ipairs(rules) do
      if M.matches(spec, w) then
        matched[#matched + 1] = spec
      end
    end
    local claimed
    for _, spec in ipairs(matched) do
      if spec.workspace ~= nil then
        claimed = spec.workspace
        break
      end
    end

    lines[#lines + 1] = ("[%d] class=%s  initialClass=%s  xwayland=%s"):format(
      i,
      w.class or "?",
      w.initial_class or "?",
      tostring(w.xwayland or false)
    )
    lines[#lines + 1] = ("    title:   %s"):format(w.title or "")
    local ws = w.workspace
    lines[#lines + 1] = ("    actual:  %s"):format(
      ws and ("workspace " .. tostring(ws.id) .. ' "' .. tostring(ws.name or "") .. '"') or "none"
    )
    if #matched == 0 then
      lines[#lines + 1] = "    matched: none"
    else
      for _, spec in ipairs(matched) do
        lines[#lines + 1] = ("    matched: %s (via %s)  %s"):format(
          spec.name or "rule",
          hit_fields(spec, w),
          spec.workspace ~= nil and ("claims " .. describe_workspace(spec.workspace)) or "no workspace claim"
        )
      end
    end
    if claimed ~= nil and workspace_matches_claim(claimed, ws) then
      lines[#lines + 1] = "    verdict: OK"
    elseif claimed ~= nil then
      lines[#lines + 1] = ("    verdict: MISMATCH — expected %s"):format(describe_workspace(claimed))
      mismatches = mismatches + 1
    else
      lines[#lines + 1] = "    verdict: no workspace rule claims this window"
    end
    if w.class ~= w.initial_class then
      lines[#lines + 1] = ("    note:    class changed since map (%s -> %s)"):format(
        w.initial_class or "?",
        w.class or "?"
      ) .. "; rules keyed on initialClass are missed"
    end
  end
  lines[#lines + 1] = ("%d windows, %d rules, %d mismatched"):format(#windows, #rules, mismatches)
  return table.concat(lines, "\n")
end

return M
