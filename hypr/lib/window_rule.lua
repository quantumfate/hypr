local M = {}

---Bulk tag-assign matches with a single tag (e.g. "+pip")
---@param matches Match[]
---@param tag string
function M.tag_matches(matches, tag)
	for _, match in ipairs(matches) do
		hl.window_rule({ match = match, tag = tag })
	end
end

---Apply a tag scope: tag the matches, then apply combined props referencing the bare tag
---@param scope WindowRuleScope
function M.apply_scope(scope)
	M.tag_matches(scope.matches, scope.tag)
	if scope.props then
		local spec = { match = { tag = scope.tag:gsub("^%+", "") } }
		for k, v in pairs(scope.props) do
			spec[k] = v
		end
		hl.window_rule(spec)
	end
end

---@param scopes table<string, WindowRuleScope>
function M.apply_scopes(scopes)
	for _, scope in pairs(scopes) do
		M.apply_scope(scope)
	end
end

---Assign matches to a workspace, with optional per-match extra props
---@param workspace string
---@param assigns WorkspaceAssign[]
function M.apply_workspace(workspace, assigns)
	for _, a in ipairs(assigns) do
		local spec = { match = a.match, workspace = workspace }
		if a.props then
			for k, v in pairs(a.props) do
				spec[k] = v
			end
		end
		hl.window_rule(spec)
	end
end

---@param assigns_map table<string, WorkspaceAssign[]>
function M.apply_workspace_assigns(assigns_map)
	for ws, list in pairs(assigns_map) do
		M.apply_workspace(ws, list)
	end
end

---Apply one-off rules (match + arbitrary props combined per rule)
---@param rules WindowRuleRule[]
function M.apply_rules(rules)
	for _, r in ipairs(rules) do
		local spec = { match = r.match }
		for k, v in pairs(r.props) do
			spec[k] = v
		end
		hl.window_rule(spec)
	end
end

---Apply named window rules
---@param named table<string, NamedWindowRule>
function M.apply_named(named)
	for _, r in pairs(named) do
		local spec = { name = r.name, match = r.match }
		for k, v in pairs(r.props) do
			spec[k] = v
		end
		hl.window_rule(spec)
	end
end

return M
