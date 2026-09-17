--- Enforces LEO-342: no hand-wired `special:` workspace remains outside the
--- allowlist below. A new `special:` selector must be added here deliberately.
local t = require("tests.harness")

-- Exempt: engine internals (hold mechanism, alt-tab) and the shelf drawers
-- (docs/shelves.md). `special:magic` (hypr/lib/minimize.lua) has no decided
-- replacement (LEO-334 gave none) and stays until one lands.
local ALLOWED = {
  "hyprfocus%-held",
  "alttab",
  "shelf%-[%w-]+",
  "magic",
}

local function allowed(name)
  for _, pattern in ipairs(ALLOWED) do
    if name:match("^" .. pattern .. "$") then
      return true
    end
  end
  return false
end

t.describe("special workspace allowlist", function()
  t.it("every `special:<name>` in hypr/ conf/ bin/ is exempt", function()
    local p = assert(io.popen("grep -rhoE 'special:[A-Za-z0-9_-]+' hypr conf bin 2>/dev/null"))
    local offenders = {}
    for line in p:lines() do
      local name = line:match("^special:(.+)$")
      if name and not allowed(name) then
        table.insert(offenders, line)
      end
    end
    p:close()
    t.eq("", table.concat(offenders, ", "), "non-exempt special workspace found")
  end)
end)
