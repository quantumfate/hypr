-- Test fixtures stub the runtime: partial `hl` objects, repeated assignments
-- to the module handles, and lookups the type system cannot prove non-nil.
-- The stub shape is the contract under test; these diagnostics read every
-- deliberately-hacked accessor as a mistake and bury real signals.
---@diagnostic disable: duplicate-set-field, need-check-nil, missing-fields, undefined-field, different-requires
local t = require("tests.harness")
local submap = require("hypr.lib.submap")

t.describe("submap.tree", function()
  t.it("builds the root open bind and the group's own binds under its submap", function()
    submap.tree({
      mods = { "SUPER", "s" },
      name = "root",
      desc = "Root group",
      entries = {
        { key = "a", desc = "Leaf A", action = hl.dsp.exec_cmd("a") },
        { key = "b", desc = "Leaf B", action = hl.dsp.exec_cmd("b") },
      },
    })

    -- The opener bind lives wherever it was pressed from — outside any
    -- submap this test defined, i.e. the stub's root ("").
    local opener
    for _, b in ipairs(hl.binds) do
      if b.key == "+SUPER+s+" then
        opener = b
      end
    end
    t.ok(opener, "expected an opener bind for +SUPER+s+")
    t.eq("Root group…", opener.opts.description)

    local leaf_a, leaf_b
    for _, b in ipairs(hl.binds) do
      if b.submap == "root" and b.key == "+a+" then
        leaf_a = b
      end
      if b.submap == "root" and b.key == "+b+" then
        leaf_b = b
      end
    end
    t.ok(leaf_a, "expected leaf a bound inside the root submap")
    t.eq("Leaf A", leaf_a.opts.description)
    t.ok(leaf_b, "expected leaf b bound inside the root submap")
  end)

  t.it("nests a group entry into its own child submap, named '<parent>-<key>' by default", function()
    submap.tree({
      mods = { "SUPER", "n" },
      name = "parent",
      entries = {
        {
          key = "c",
          desc = "Child group",
          entries = {
            { key = "x", desc = "Leaf X", action = hl.dsp.exec_cmd("x") },
          },
        },
      },
    })

    local child_leaf
    for _, b in ipairs(hl.binds) do
      if b.submap == "parent-c" and b.key == "+x+" then
        child_leaf = b
      end
    end
    t.ok(child_leaf, "expected the nested group's leaf to live under submap 'parent-c'")
  end)

  t.it("honors an explicit child `name` instead of the default '<parent>-<key>'", function()
    submap.tree({
      mods = { "SUPER", "m" },
      name = "outer",
      entries = {
        {
          key = "z",
          name = "custom-name",
          entries = {
            { key = "y", desc = "Leaf Y", action = hl.dsp.exec_cmd("y") },
          },
        },
      },
    })

    local found = false
    for _, b in ipairs(hl.binds) do
      if b.submap == "custom-name" and b.key == "+y+" then
        found = true
      end
    end
    t.ok(found, "expected the named child submap to be used verbatim")
  end)
end)

t.describe("binding arity of trees", function()
  t.it("an enter-only leaf follows the tree it is a door into", function()
    -- Withholding a tree must take the entering key with it: in work mode,
    -- the Dofus key should not remain a live bind that only opens an
    -- empty submap (LEO-303's first slice).
    local binds = require("hypr.hyprfocus.binds")
    local before = binds.size("opened-tree")
    submap.tree({
      mods = { "SUPER", "o" },
      name = "acc-tree-1",
      entries = {
        { key = "d", desc = "Door", opens = "opened-tree", action = function() end },
      },
    })
    t.eq(before, binds.size("opened-tree"), "the door counts as the destination tree's")
  end)

  t.it("escape stays at whatever tree the submap lives in, never the withheld one", function()
    -- Not the architecture's final word (LEO-303 owns that): the checked
    -- invariant is that the per-submap escape does not upholstery the submap
    -- itself, since withholding that tree would take the exit with the room.
    local binds = require("hypr.hyprfocus.binds") or {}
    local before = binds.size("acc-tree-2")
    submap.tree({
      mods = { "SUPER", "p" },
      name = "acc-tree-2",
      entries = {
        { key = "x", desc = "Leaf", action = function() end },
      },
    })
    t.eq(before, binds.size("acc-tree-2"), "escape belongs to the tree the room evaluates out of")
  end)
end)
