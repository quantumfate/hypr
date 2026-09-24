-- Lifecycle log sink (LEO-352, docs/lifecycle.md Part B "Decision record").
--
-- One journal entry per decision, with the record's own fields written as
-- structured journal fields (upper-cased) plus `SYSLOG_IDENTIFIER=hyprfocus`,
-- so `,hyprfocus log --trace <address>` and the `logs` workspace can filter
-- by window without parsing free text out of a message.
--
-- Sink: the systemd journal via the user manager. The lifecycle contract's
-- "Sink (decided)" section is the final word on this — no JSONL file, even
-- though an earlier draft (N1) mentioned one.
--
-- Why `logger --journald` and not `systemd-cat`: `systemd-cat` only sets an
-- identifier and forwards stdin as the message, one line per entry — it has
-- no way to attach the rest of a decision record (trace, scene, workspace,
-- ...) as separate fields. `logger --journald` reads a structured entry
-- (`FIELD=value` lines, terminated by a blank line) from stdin and writes it
-- to the journal verbatim, which is exactly the shape a decision record is
-- already in.
--
-- Non-blocking: this module never runs `logger` synchronously on the
-- compositor thread. It hands the command to `hl.dispatch(hl.dsp.exec_cmd
-- (...))`, the same fire-and-forget spawn every other exec in this repo
-- already uses (see the companion spawn in hypr/events/scene.lua) -- the
-- compositor forks the shell and returns immediately, so a decision on the
-- hot path (window.open, mode apply) never waits on `logger` or the journal.
-- The payload is base64-encoded so a title or reason containing quotes, `$`,
-- backticks or newlines cannot break the shell command it rides in.
--
-- No-op-safe: under `tests/hl_stub.lua` (and any other incomplete `hl`)
-- `emit` silently does nothing rather than erroring, so pure decision-record
-- builders can be tested without a compositor and without asserting on log
-- output (specs stub this module and assert on the records it was called
-- with instead -- see tests/trace_spec.lua).
local M = {}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

---Minimal pure-Lua base64 encoder. Decision records are a handful of short
---fields, so there is no need to shell out or depend on a library for this.
---@param data string
---@return string
local function base64(data)
  local bits = data:gsub(".", function(char)
    local out, byte = "", char:byte()
    for i = 8, 1, -1 do
      out = out .. ((byte % (2 ^ i) - byte % (2 ^ (i - 1)) > 0) and "1" or "0")
    end
    return out
  end)
  bits = bits .. ("0"):rep((6 - #bits % 6) % 6)
  local encoded = bits:gsub("%d%d%d%d%d%d", function(sextet)
    local value = 0
    for i = 1, 6 do
      value = value + (sextet:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
    end
    return B64:sub(value + 1, value + 1)
  end)
  return encoded .. ("="):rep((3 - #data % 3) % 3)
end

---Journal field names are uppercase ASCII/digits/underscore and may not
---start with a digit or underscore; record keys here are already
---lower_snake_case identifiers, so uppercasing plus a narrow sanitize covers
---every field this codebase emits.
---@param key string
---@return string
local function field_name(key)
  local name = key:upper():gsub("[^A-Z0-9_]", "_")
  if name:match("^[0-9_]") then
    name = "F_" .. name
  end
  return name
end

---The journald stdin lines for one record, terminated by the blank line that
---ends a structured entry.
---@param record table
---@return string[]
local function record_lines(record)
  local message = ("%s.%s %s %s")
    :format(record.stage, record.event, record.decision or "", record.reason or "")
    :gsub("%s+$", "")

  local lines = { "SYSLOG_IDENTIFIER=hyprfocus" }
  for key, value in pairs(record) do
    if value ~= nil and value ~= "" then
      lines[#lines + 1] = ("%s=%s"):format(field_name(key), tostring(value))
    end
  end
  lines[#lines + 1] = "MESSAGE=" .. message
  lines[#lines + 1] = "" -- structured stdin entries end with a blank line
  return lines
end

---@param lines string[]
local function spawn(lines)
  local payload = base64(table.concat(lines, "\n"))
  local cmd = ("sh -c 'echo %s | base64 -d | logger --journald'"):format(payload)
  pcall(function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
  end)
end

-- Batching for watchdog-bounded contexts: an `hl.timer` callback is killed
-- after 50ms on this build (spiked live, "execution timed out in hl.timer
-- callback"), and a mode apply emitting ~20 records spends 30ms+ of that on
-- fork/exec if each dispatches its own logger. `begin_batch` queues records
-- instead; `end_batch` flushes the queue as ONE spawn carrying every record,
-- entries blank-line separated, so the journal still gets one entry per
-- decision. Emits outside a batch dispatch immediately, as before. Not
-- re-entrant: one batch at a time, bracketed by the caller (a mode apply).
local batching = false
---@type table[]
local queue = {}

---Write one decision record to the journal. `record.stage` and
---`record.event` are required (they name the log line); every other field is
---optional and only written when present, so callers can pass a partial
---record without a nil check at every field.
---@param record table decision record (docs/lifecycle.md Part B field list)
function M.emit(record)
  if type(record) ~= "table" or not record.stage or not record.event then
    return
  end
  if batching then
    queue[#queue + 1] = record
    return
  end
  if not hl or not hl.dispatch or not hl.dsp or not hl.dsp.exec_cmd then
    return -- no compositor to hand the spawn to: no-op, never error
  end
  spawn(record_lines(record))
end

---Start queueing records instead of dispatching them. Pair with `end_batch`.
function M.begin_batch()
  batching = true
end

---Flush every queued record and resume immediate dispatch. `logger
---`--journald` reads ONE structured entry per invocation (spiked live: the
---second entry of a multi-entry stdin is silently dropped), so the batch
---spawns one shell that pipes each record to its own logger — the compositor
---pays for a single fork either way, the record spawns happen off-thread.
function M.end_batch()
  local records = queue
  queue = {}
  batching = false
  if not hl or not hl.dispatch or not hl.dsp or not hl.dsp.exec_cmd then
    return
  end
  local pipes = {}
  for _, record in ipairs(records) do
    local payload = base64(table.concat(record_lines(record), "\n"))
    pipes[#pipes + 1] = ("echo %s | base64 -d | logger --journald"):format(payload)
  end
  if #pipes > 0 then
    pcall(function()
      hl.dispatch(hl.dsp.exec_cmd(("sh -c '%s'"):format(table.concat(pipes, "; "))))
    end)
  end
end

return M
