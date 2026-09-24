-- Open-time group decisions (LEO-369).
--
-- Compile-time tag->group rule chains never fire (see hypr/scene/compile.lua
-- header): grouping is decided here instead, once per `window.open` /
-- `window.move_to_workspace` event, against the live `HL.Group` object
-- interface spiked live: `group.toggle` seeds a group without moving focus,
-- `window.group:add`/`:remove` join and eject.
--
-- Pure: this module returns a decision, never calls `hl`. The executor
-- (hypr/events/scene.lua) dispatches and logs it.
local spec_lib = require("hypr.scene.spec")

local M = {}

---@class Scene.GroupDecision
---@field action "seed"|"join"|"eject"|"none"
---@field window HL.Window the window the triggering event fired for
---@field members HL.Window[]? seed: every ungrouped block peer to fold in (w included), lowest address first
---@field target HL.Window? join: a window already in the winning group
---@field block Scene.Block? the group block `window`'s class matched

---A group's identity is the lowest address among its live members: group
---objects returned by `hl.get_window` are not comparable across reads (the
---same fact `hypr/scene/provider.lua`'s `window_tile` already relies on),
---only the member list is.
---@param w HL.Window
---@return string? key
local function group_key(w)
  if not w.group then
    return nil
  end
  local members = w.group.members
  members = (members and members.title) and { members } or (members or {})
  local key
  for _, member in ipairs(members) do
    if member.address and (not key or member.address < key) then
      key = member.address
    end
  end
  return key
end
M.group_key = group_key

---The group block `class` (and, for a slot block, `tags`) belongs to, or nil
---for a class this scene either does not declare or declares in a
---non-group block.
---@param spec Scene.Spec
---@param class string?
---@param tags string[]?
---@return Scene.Block?
local function group_block_for(spec, class, tags)
  local block = spec_lib.block_for(spec, class, tags)
  return block and block.group and block or nil
end

---The one group action `w` needs, given every window currently live on its
---workspace. `live` is `hl.get_windows()` (or a stub's stand-in).
---@param spec Scene.Spec
---@param w HL.Window
---@param live HL.Window[]
---@return Scene.GroupDecision
function M.decide(spec, w, live)
  if not w or not w.workspace then
    return { action = "none", window = w }
  end
  local block = group_block_for(spec, w.class, w.tags)

  if not block then
    -- Not a group-block class: `auto_group` can still swallow it into a
    -- neighboring block's group (AGENTS.md "Hyprland primitives"); eject.
    if w.group then
      return { action = "eject", window = w }
    end
    return { action = "none", window = w }
  end

  if w.group then
    -- A group block admits ONLY its own classes (AGENTS.md: "a group must
    -- reject windows whose class is not explicitly allowed"), and `auto_group`
    -- still swallows across blocks even after compiling the rules. Being in
    -- *a* group was read as being in the *right* one, so two project blocks
    -- opened on the same scene merged into one group of eight (spiked live)
    -- and nothing ever ejected them. Check the company, not just membership.
    local members = w.group.members
    members = (members and members.title) and { members } or (members or {})
    for _, member in ipairs(members) do
      if member.address ~= w.address and group_block_for(spec, member.class, member.tags) ~= block then
        return { action = "eject", window = w, block = block }
      end
    end
    return { action = "none", window = w, block = block } -- already a member
  end

  -- A deck scene parks the members it is not showing on a hold workspace
  -- (hypr/scene/deck.lua). That is a parking place for this scene's own
  -- windows, not a different home, so a block-mate sitting there is still a
  -- peer: matching only `w`'s own workspace meant a project whose windows the
  -- deck held could never form its group at all -- each window opened alone,
  -- was parked before any peer arrived, and every later peer looked at an
  -- empty workspace (spiked live: four `Proj-hypr` windows, `grouped = 0`,
  -- three of them on `special:deck-hold`).
  local ws_name = w.workspace.name
  local hold = require("hypr.scene.deck_provider").HOLD
  local function same_home(name)
    return name == ws_name or name == hold
  end
  local peers = {}
  for _, other in ipairs(live) do
    if
      other.address ~= w.address
      and other.workspace
      and same_home(other.workspace.name)
      and group_block_for(spec, other.class, other.tags) == block
    then
      peers[#peers + 1] = other
    end
  end

  -- The group already holding the most of the block's tiles wins (AGENTS.md
  -- "Derive a block's group each pass"): derived fresh from live windows
  -- every time, never remembered, so a block `auto_group` splits in two
  -- still converges on one.
  local counts, anchor_by_key = {}, {}
  local best_key, best_count
  for _, peer in ipairs(peers) do
    local key = group_key(peer)
    if key then
      counts[key] = (counts[key] or 0) + 1
      anchor_by_key[key] = anchor_by_key[key] or peer
      if not best_count or counts[key] > best_count then
        best_key, best_count = key, counts[key]
      end
    end
  end

  if best_key then
    return { action = "join", window = w, target = anchor_by_key[best_key], block = block }
  end

  if #peers == 0 then
    return { action = "none", window = w, block = block } -- nothing yet to group with
  end

  -- No peer is grouped yet: fold every currently ungrouped peer plus `w`
  -- into one group in this pass. A peer that opened first and never got
  -- folded in has no future event of its own to catch it.
  local members = { w }
  for _, peer in ipairs(peers) do
    members[#members + 1] = peer
  end
  table.sort(members, function(a, b)
    return a.address < b.address
  end)

  return { action = "seed", window = w, members = members, block = block }
end

return M
