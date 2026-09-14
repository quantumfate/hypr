--- The hyprfocus resolver: base + mode deltas -> one complete desk.
---
--- The resolver is pure, so these are plain tables — no stub compositor, no
--- store, no timers. If a mode's meaning is wrong it is wrong here.
local t = require("tests.harness")
local resolve = require("hypr.hyprfocus.resolve")

local function declaration(modes, base)
  return {
    version = 1,
    base = base or {
      workspaces = { "code", "creative", "media", "gaming", "logs" },
      bindings = { "global", "nav", "window", "dofus", "llm" },
      services = { "theme-auto", "obsidian", "linear-sync", "state-backup" },
      projects = { "nvim", "quickshell" },
      scenes = {
        code = { blocks = { { classes = { "Kitty-Main" }, order = 1 } } },
        gaming = { blocks = { { classes = { "Dofus.x64" }, order = 1, group = true } } },
      },
      notify = { default = "show", ["linear-sync"] = "queue" },
    },
    modes = modes,
  }
end

local function names(list)
  return table.concat(list, ",")
end

t.describe("inheritance", function()
  t.it("a mode that declares nothing is the base", function()
    local desk = resolve.resolve(declaration({ neutral = { name = "Neutral" } }), "neutral")
    t.eq("code,creative,media,gaming,logs", names(desk.workspaces))
    t.eq("theme-auto,obsidian,linear-sync,state-backup", names(desk.services))
  end)

  t.it("carries the mode id on the resolved desk", function()
    local desk = resolve.resolve(declaration({ neutral = { name = "Neutral" } }), "neutral")
    t.eq("neutral", desk.mode)
  end)
end)

t.describe("delta grammar", function()
  t.it("`only` replaces the base's set", function()
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", workspaces = { only = { "gaming" } } },
    })
    t.eq("gaming", names(resolve.resolve(d, "game").workspaces))
  end)

  t.it("`remove` subtracts and keeps declaration order", function()
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", services = { remove = { "obsidian", "linear-sync" } } },
    })
    t.eq("theme-auto,state-backup", names(resolve.resolve(d, "game").services))
  end)

  t.it("`add` appends after the base, in the order the mode wrote them", function()
    local d = declaration({
      neutral = { name = "N" },
      llm = { name = "LLM", bindings = { only = { "global" } } },
    })
    d.modes.llm.bindings = { only = { "global", "llm" } }
    t.eq("global,llm", names(resolve.resolve(d, "llm").bindings))

    d.modes.llm.bindings = { remove = { "dofus" }, add = { "llm" } }
    t.eq("global,nav,window,llm", names(resolve.resolve(d, "llm").bindings))
  end)

  t.it("`add` of something already present does not duplicate it", function()
    local d = declaration({
      neutral = { name = "N" },
      llm = { name = "LLM", bindings = { add = { "nav" } } },
    })
    t.eq("global,nav,window,dofus,llm", names(resolve.resolve(d, "llm").bindings))
  end)

  t.it("`remove` of something absent is not an error", function()
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", projects = { remove = { "not-a-project" } } },
    })
    t.eq("nvim,quickshell", names(resolve.resolve(d, "game").projects))
  end)

  t.it("rejects `only` combined with `add`", function()
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", workspaces = { only = { "gaming" }, add = { "logs" } } },
    })
    local ok, err = pcall(resolve.resolve, d, "game")
    t.ok(not ok, "expected a failure")
    t.ok(tostring(err):match("cannot be combined"), "message names the conflict: " .. tostring(err))
  end)
end)

t.describe("unknown names", function()
  t.it("fail at resolve time, naming the mode and kind", function()
    -- A typo must fail when the declaration is read, not resolve into a desk
    -- that is quietly missing a workspace at the moment it is entered.
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", workspaces = { only = { "gamming" } } },
    })
    local ok, err = pcall(resolve.resolve, d, "game")
    t.ok(not ok, "expected a failure")
    t.ok(tostring(err):match("unknown workspaces 'gamming'"), tostring(err))
    t.ok(tostring(err):match("game"), "message names the mode")
  end)

  t.it("an unknown mode is an error, not an empty desk", function()
    local ok = pcall(resolve.resolve, declaration({ neutral = { name = "N" } }), "nope")
    t.ok(not ok)
  end)
end)

t.describe("scenes", function()
  t.it("come from the base", function()
    local desk = resolve.resolve(declaration({ neutral = { name = "N" } }), "neutral")
    t.ok(desk.scenes.code and desk.scenes.gaming)
  end)

  t.it("are dropped when their workspace is not admitted", function()
    -- A resolved desk must never carry geometry for a workspace that is not
    -- there; the layout would have nothing to apply it to.
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", workspaces = { only = { "gaming" } } },
    })
    local desk = resolve.resolve(d, "game")
    t.ok(desk.scenes.gaming, "the admitted workspace keeps its scene")
    t.eq(nil, desk.scenes.code, "the withdrawn one does not")
  end)
end)

t.describe("notification routing", function()
  t.it("merges a mode's overrides onto the base", function()
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", notify = { default = "drop" } },
    })
    local desk = resolve.resolve(d, "game")
    t.eq("drop", desk.notify.default, "the mode's fallback wins")
    t.eq("queue", desk.notify["linear-sync"], "an unmentioned source keeps the base's rule")
  end)
end)

t.describe("revocation", function()
  t.it("defaults windows to hold and everything else to retire", function()
    -- Holding buys attention; retiring buys capacity. A workspace's windows
    -- should come back; a sync timer's cost is the reason it was revoked.
    local desk = resolve.resolve(declaration({ neutral = { name = "N" } }), "neutral")
    t.eq("hold", resolve.revocation(desk, "workspaces", "code"))
    t.eq("hold", resolve.revocation(desk, "projects", "nvim"))
    t.eq("retire", resolve.revocation(desk, "services", "linear-sync"))
    t.eq("retire", resolve.revocation(desk, "bindings", "dofus"))
  end)

  t.it("honours an explicit override", function()
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", revoke = { nvim = "retire" } },
    })
    t.eq("retire", resolve.revocation(resolve.resolve(d, "game"), "projects", "nvim"))
  end)
end)

t.describe("resolve_all", function()
  t.it("resolves every mode, so a broken one fails at load", function()
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", workspaces = { only = { "gaming" } } },
    })
    local all = resolve.resolve_all(d)
    t.eq("code,creative,media,gaming,logs", names(all.neutral.workspaces))
    t.eq("gaming", names(all.game.workspaces))
  end)

  t.it("propagates a failure from any single mode", function()
    local d = declaration({
      neutral = { name = "N" },
      broken = { name = "Broken", services = { only = { "ghost" } } },
    })
    t.ok(not pcall(resolve.resolve_all, d))
  end)
end)

t.describe("purity", function()
  t.it("does not mutate the declaration it was given", function()
    -- The resolver is called on every mode change; a resolver that edited its
    -- input would make the second call mean something different from the first.
    local d = declaration({
      neutral = { name = "N" },
      game = { name = "Game", services = { remove = { "obsidian" } } },
    })
    resolve.resolve(d, "game")
    t.eq("theme-auto,obsidian,linear-sync,state-backup", names(d.base.services))
    t.ok(d.base.scenes.code, "base scenes survive a mode that drops them")
  end)
end)

t.describe("requirements", function()
  --- Obsidian is the shape the model has to carry: a project whose usefulness
  --- depends on background work the user never thinks about by name.
  local function obsidian(modes)
    return {
      version = 1,
      base = {
        workspaces = { "code", "study", "gaming" },
        bindings = { "global" },
        services = { "theme-auto", "obsidian", "obsidian-index", "linear-sync" },
        projects = { "nvim", "obsidian" },
        requires = {
          ["project:obsidian"] = { "service:obsidian", "workspace:study" },
          ["service:obsidian"] = { "service:obsidian-index", "service:linear-sync" },
        },
      },
      modes = modes,
    }
  end

  t.it("admitting a project pulls in the services it needs", function()
    local d = obsidian({
      neutral = { name = "N" },
      study = {
        name = "Study",
        projects = { only = { "obsidian" } },
        services = { only = { "theme-auto" } },
      },
    })
    local desk = resolve.resolve(d, "study")
    t.eq("theme-auto,obsidian,obsidian-index,linear-sync", names(desk.services))
  end)

  t.it("follows requirements transitively", function()
    -- The mode names obsidian; the sync timer arrives two edges away without
    -- the mode ever mentioning it.
    local d = obsidian({
      neutral = { name = "N" },
      study = {
        name = "Study",
        projects = { only = { "obsidian" } },
        services = { only = {} },
      },
    })
    local desk = resolve.resolve(d, "study")
    t.eq("obsidian,obsidian-index,linear-sync", names(desk.services))
  end)

  t.it("crosses kinds, so a project can require its workspace", function()
    local d = obsidian({
      neutral = { name = "N" },
      study = {
        name = "Study",
        projects = { only = { "obsidian" } },
        workspaces = { only = { "code" } },
      },
    })
    t.eq("code,study", names(resolve.resolve(d, "study").workspaces))
  end)

  t.it("adds a shared requirement once", function()
    local d = obsidian({ neutral = { name = "N" } })
    d.base.requires["project:nvim"] = { "service:linear-sync" }
    local desk = resolve.resolve(d, "neutral")
    local count = 0
    for _, name in ipairs(desk.services) do
      if name == "linear-sync" then
        count = count + 1
      end
    end
    t.eq(1, count, "a diamond resolves to one entry, not two")
  end)

  t.it("terminates on a cycle instead of recursing", function()
    local d = obsidian({ neutral = { name = "N" } })
    d.base.requires["service:linear-sync"] = { "service:obsidian" }
    local desk = resolve.resolve(d, "neutral")
    t.ok(#desk.services >= 4, "the cycle resolved rather than hanging")
  end)

  t.it("does not pull anything in for a resource that is not admitted", function()
    local d = obsidian({
      neutral = { name = "N" },
      game = { name = "Game", projects = { only = {} }, services = { only = { "theme-auto" } } },
    })
    t.eq("theme-auto", names(resolve.resolve(d, "game").services))
  end)
end)

t.describe("requirement conflicts", function()
  local function d_with(mode)
    return {
      version = 1,
      base = {
        services = { "obsidian", "linear-sync" },
        projects = { "obsidian" },
        requires = { ["project:obsidian"] = { "service:linear-sync" } },
      },
      modes = { neutral = { name = "N" }, study = mode },
    }
  end

  t.it("reports `remove` contradicting a requirement rather than guessing", function()
    -- Adding it anyway ignores what the mode said; omitting it breaks the
    -- thing that needed it. Neither is a safe default, so it is an error.
    local ok, err = pcall(
      resolve.resolve,
      d_with({
        name = "Study",
        services = { remove = { "linear-sync" } },
      }),
      "study"
    )
    t.ok(not ok, "expected a failure")
    t.ok(tostring(err):match("removed but required by project:obsidian"), tostring(err))
  end)

  t.it("lets `only` be widened by a requirement", function()
    -- `only` says what to inherit, not what to forbid — so a narrow mode still
    -- ends up with a working app rather than a broken one.
    local desk = resolve.resolve(
      d_with({
        name = "Study",
        services = { only = { "obsidian" } },
      }),
      "study"
    )
    t.eq("obsidian,linear-sync", names(desk.services))
  end)

  t.it("rejects a malformed reference", function()
    local d = d_with({ name = "Study" })
    d.base.requires["project:obsidian"] = { "linear-sync" }
    local ok, err = pcall(resolve.resolve, d, "study")
    t.ok(not ok)
    t.ok(tostring(err):match("malformed requires reference"), tostring(err))
  end)
end)

t.describe("wants: soft edges", function()
  --- The distinction the seed forced: Obsidian *uses* its indexer and sync but
  --- runs without them, so a media mode can keep the window and stop the
  --- background work. Modelling that as `requires` makes shipping behaviour
  --- impossible to express.
  local function suite(mode)
    return {
      version = 1,
      base = {
        services = { "obsidian", "obsidian-index", "linear-sync" },
        wants = { ["service:obsidian"] = { "service:obsidian-index", "service:linear-sync" } },
      },
      modes = { neutral = { name = "N" }, media = mode },
    }
  end

  t.it("pulls a wanted companion in by default", function()
    t.eq("obsidian,obsidian-index,linear-sync", names(resolve.resolve(suite({ name = "Media" }), "media").services))
  end)

  t.it("yields to an explicit removal instead of reporting a conflict", function()
    local desk =
      resolve.resolve(suite({ name = "Media", services = { remove = { "obsidian-index", "linear-sync" } } }), "media")
    t.eq("obsidian", names(desk.services), "the window stays, the background work goes")
  end)

  t.it("still widens an `only` that did not mention it", function()
    local desk = resolve.resolve(suite({ name = "Media", services = { only = { "obsidian" } } }), "media")
    t.eq("obsidian,obsidian-index,linear-sync", names(desk.services))
  end)

  t.it("does not follow the edges of something that was removed", function()
    local d = suite({ name = "Media", services = { remove = { "obsidian" } } })
    d.base.wants["service:obsidian-index"] = { "service:linear-sync" }
    d.base.services = { "obsidian", "obsidian-index", "linear-sync" }
    local desk = resolve.resolve(d, "media")
    t.eq("obsidian-index,linear-sync", names(desk.services), "removing obsidian drops its subtree, not the base")
  end)

  t.it("a hard requirement still reports, next to a soft one", function()
    local d = suite({ name = "Media", services = { remove = { "linear-sync" } } })
    d.base.requires = { ["service:obsidian"] = { "service:linear-sync" } }
    d.base.wants = {}
    t.ok(not pcall(resolve.resolve, d, "media"))
  end)
end)
