local M = {}

---Bulk tag-assign matches with a single tag (e.g. "+pip")
---@param props_list WindowRuleProps[]
---@param tag string
function M.tag_props(props_list, tag)
  for _, props in ipairs(props_list) do
    hl.window_rule({ match = props, tag = tag })
  end
end

---Apply a tag scope: tag the matches, then apply combined props referencing the bare tag
---@param tag string
---@param effects WindowRuleEffects
function M.tag_set_effects(tag, effects)
  local opts = { match = { tag = tag } }

  if effects.dynamic then
    for option, value in pairs(effects.dynamic) do
      opts[option] = value
    end
  end

  if effects.static then
    for option, value in pairs(effects.static) do
      opts[option] = value
    end
  end
  hl.window_rule(opts)
end

return M
