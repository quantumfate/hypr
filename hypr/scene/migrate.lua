-- The one-time fold of the retired scenes store into the declaration.
--
-- Scenes used to live twice: `$QF_STORE/scenes.json` (seeded from a Lua
-- default) and the hyprfocus declaration's `base.scenes`. The declaration is
-- the single table now (docs/scenes.md, "Source of truth"). A scene in the
-- legacy document that still equals the retired seed carries no user intent,
-- so it is dropped; a scene the user edited is written into `base.scenes`
-- once. The seed itself is gone, so it is remembered only as a fingerprint
-- per scene — never as a second copy of the table.
local M = {}

---Checksums of the retired seed's scenes (generation 3), by scene name.
M.SEED = {
  ["code"] = 2752552524,
  ["communication"] = 183968044,
  ["dofus"] = 1092859007,
  ["logs"] = 937524268,
  ["lutris"] = 303905177,
  ["media"] = 3569259209,
  ["obsidian-linear"] = 4247076888,
  ["pokemon"] = 1942861926,
  ["proton"] = 325973127,
  ["steam"] = 1073077608,
  ["steam-games"] = 16358421,
}

---Deterministic text for a raw scene: keys sorted, empty tables and nils
---dropped, so a store written by another encoder (`[]` vs `{}`) still agrees.
---@param value any
---@return string?
local function canonical(value)
  if type(value) ~= "table" then
    if type(value) == "number" and value == math.floor(value) then
      return ("%d"):format(value)
    end
    return value ~= nil and ("%s:%s"):format(type(value), tostring(value)) or nil
  end
  local parts = {}
  if #value > 0 then
    for _, item in ipairs(value) do
      parts[#parts + 1] = canonical(item) or "null"
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = tostring(key)
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local text = canonical(value[key])
    if text and text ~= "{}" then
      parts[#parts + 1] = key .. "=" .. text
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

---A 32-bit FNV-1a checksum of a scene's canonical text.
---@param scene table
---@return integer
function M.fingerprint(scene)
  local text, hash = canonical(scene) or "", 2166136261
  for i = 1, #text do
    hash = hash ~ text:byte(i)
    hash = (hash * 16777619) % 4294967296
  end
  return hash
end

---Fold a legacy scenes document into a declaration. Pure: the declaration is
---returned modified in place and the caller persists it.
---@param declaration table the hyprfocus declaration
---@param legacy table? the retired `scenes.json` document
---@param seed table<string, integer>? fingerprints of unedited scenes
---@return table declaration, string[] folded scene names, sorted
function M.fold(declaration, legacy, seed)
  seed = seed or M.SEED
  local folded = {}
  local scenes = type(legacy) == "table" and legacy.scenes
  if type(scenes) ~= "table" then
    return declaration, folded
  end
  declaration.base = declaration.base or {}
  declaration.base.scenes = declaration.base.scenes or {}
  for name, scene in pairs(scenes) do
    if type(scene) == "table" and seed[name] ~= M.fingerprint(scene) then
      declaration.base.scenes[name] = scene
      folded[#folded + 1] = name
    end
  end
  table.sort(folded)
  return declaration, folded
end

return M
