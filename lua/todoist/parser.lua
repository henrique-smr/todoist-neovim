-- Parser for converting between Todoist data and markdown
local M = {}

local config = require("todoist.config")

function M.project_to_markdown(project_data)
	local lines = {}
	local extmarks = {}

	-- Add project title
	local project_name = "Untitled Project"
	if project_data.project and project_data.project.name then
		project_name = project_data.project.name
	end

	table.insert(lines, "# " .. project_name)
	table.insert(lines, "")

	if config.is_debug() then
		print("DEBUG: Project data:", vim.inspect(project_data))
		print("DEBUG: Tasks count:", #(project_data.tasks or {}))
		print("DEBUG: Sections count:", #(project_data.sections or {}))
	end

	-- Group tasks by section
	local sections = {}
	local unsectioned_tasks = {}

	-- Create section lookup
	local section_lookup = {}
	for _, section in ipairs(project_data.sections or {}) do
		section_lookup[section.id] = section
		sections[section.id] = {
			section = section,
			tasks = {},
		}
	end

	-- Group tasks
	for _, task in ipairs(project_data.tasks or {}) do
		if config.is_debug() then
			print("DEBUG: Processing task:", vim.inspect(task))
		end

		if task.section_id and sections[task.section_id] then
			table.insert(sections[task.section_id].tasks, task)
		else
			table.insert(unsectioned_tasks, task)
		end
	end

	-- Add unsectioned tasks first
	if #unsectioned_tasks > 0 then
		if config.is_debug() then
			print("DEBUG: Adding", #unsectioned_tasks, "unsectioned tasks")
		end
		M.add_tasks_to_markdown(unsectioned_tasks, lines, extmarks, nil)
		table.insert(lines, "")
	end

	-- Add sectioned tasks
	for section_id, section_data in pairs(sections) do
		if #section_data.tasks > 0 then
			if config.is_debug() then
				print("DEBUG: Adding section", section_data.section.name, "with", #section_data.tasks, "tasks")
			end

			-- Add section header
			table.insert(lines, "## " .. section_data.section.name)
			table.insert(extmarks, {
				line = #lines - 1,
				col = 0,
				opts = {
					end_line = #lines - 1,
					end_col = -1,
					todoist_type = "section",
					todoist_id = section_data.section.id,
				},
			})
			table.insert(lines, "")

			M.add_tasks_to_markdown(section_data.tasks, lines, extmarks, section_id)
			table.insert(lines, "")
		end
	end

	-- If no tasks at all, add a helpful message
	if #unsectioned_tasks == 0 and vim.tbl_count(sections) == 0 then
		table.insert(lines, "_No tasks found. Start typing to add some!_")
		table.insert(lines, "")
		table.insert(lines, "## Example")
		table.insert(lines, "")
		table.insert(lines, "- [ ] Your first task")
		table.insert(lines, "  Add task description here")
		table.insert(lines, "")
		table.insert(lines, "- [x] Completed task")
	end

	if config.is_debug() then
		print("DEBUG: Final lines count:", #lines)
		print("DEBUG: Final extmarks count:", #extmarks)
	end

	return {
		lines = lines,
		extmarks = extmarks,
	}
end

function M.add_tasks_to_markdown(tasks, lines, extmarks, section_id)
	-- Build task tree
	local root_tasks = {}
	local task_children = {}

	for _, task in ipairs(tasks) do
		if config.is_debug() then
			print("DEBUG: Processing task:", vim.inspect(task))
		end
		if task.parent_id then
			if not task_children[task.parent_id] then
				task_children[task.parent_id] = {}
			end
			if config.is_debug() then
				print("DEBUG: Adding task", task.id, "as child of", task.parent_id)
			end
			table.insert(task_children[task.parent_id], task)
		else
			if config.is_debug() then
				print("DEBUG: Adding root task", task.id)
			end
			table.insert(root_tasks, task)
		end
	end

	-- Sort tasks by order if available
	table.sort(root_tasks, function(a, b)
		return (a.order or 0) < (b.order or 0)
	end)

	if config.is_debug() then
		print("DEBUG: Root tasks for section:", #root_tasks)
		for i, task in ipairs(root_tasks) do
			print("DEBUG: Root task", i, ":", task.content)
		end
	end

	-- Add tasks recursively
	for _, task in ipairs(root_tasks) do
		M.add_task_to_markdown(task, lines, extmarks, 0, task_children)
	end
end

function M.add_task_to_markdown(task, lines, extmarks, depth, task_children)
	local indent = string.rep("  ", depth)
	local checkbox = task.is_completed and "[x]" or "[ ]"
	local task_line = indent .. "- " .. checkbox .. " " .. (task.content or "")

	if config.is_debug() then
		print("DEBUG: Adding task line:", task_line)
	end

	table.insert(lines, task_line)
	table.insert(extmarks, {
		line = #lines - 1,
		col = 0,
		opts = {
			end_line = #lines - 1,
			end_col = -1,
			todoist_type = "task",
			todoist_id = task.id,
			parent_id = task.parent_id,
			section_id = task.section_id,
		},
	})

	-- Add description if exists
	if task.description and task.description ~= "" then
		table.insert(lines, "")
		local desc_lines = vim.split(task.description, "\n")
		for _, desc_line in ipairs(desc_lines) do
			table.insert(lines, indent .. "  " .. desc_line)
		end
		table.insert(lines, "")
	end

	-- Add children
	if task_children[task.id] then
		-- Sort children by order
		table.sort(task_children[task.id], function(a, b)
			return (a.order or 0) < (b.order or 0)
		end)

		if config.is_debug() then
			print("DEBUG: Adding", #task_children[task.id], "children for task:", task.content)
		end

		for _, child in ipairs(task_children[task.id]) do
			M.add_task_to_markdown(child, lines, extmarks, depth + 1, task_children)
		end
	end
end

function M.set_extmarks(buf, ns_id, extmarks)
	for _, mark in ipairs(extmarks) do
		pcall(function()
			vim.api.nvim_buf_set_extmark(buf, ns_id, mark.line, mark.col, mark.opts)
		end)
	end
end

function M.parse_markdown_to_changes(lines, extmarks)
	local changes = {
		created_sections = {},
		updated_sections = {},
		deleted_sections = {},
		created_tasks = {},
		updated_tasks = {},
		deleted_tasks = {},
	}

	-- Create lookup tables
	local extmark_lookup = {}
	for _, mark in ipairs(extmarks) do
		local data = mark[4]
		if data and data.todoist_id then
			extmark_lookup[mark[2]] = data -- line number -> extmark data
		end
	end

	local seen_ids = {}

	-- Parse lines
	for i, line in ipairs(lines) do
		local line_num = i - 1

		-- Check for section headers
		local section_title = line:match("^## (.+)$")
		if section_title then
			local extmark_data = extmark_lookup[line_num]
			if extmark_data and extmark_data.todoist_type == "section" then
				-- Existing section, check for updates
				seen_ids[extmark_data.todoist_id] = true
				-- Compare title and add to updates if different
				table.insert(changes.updated_sections, {
					id = extmark_data.todoist_id,
					name = section_title,
				})
			else
				-- New section
				table.insert(changes.created_sections, {
					name = section_title,
					line = line_num,
				})
			end
		end

		-- Check for tasks
		local indent, checkbox, content = line:match("^(%s*)%- %[([%sx])%] (.+)$")
		if content then
			local depth = math.floor(#indent / 2)
			local is_completed = checkbox == "x"

			local extmark_data = extmark_lookup[line_num]
			if extmark_data and extmark_data.todoist_type == "task" then
				-- Existing task, check for updates
				seen_ids[extmark_data.todoist_id] = true
				table.insert(changes.updated_tasks, {
					id = extmark_data.todoist_id,
					content = content,
					is_completed = is_completed,
				})
			else
				-- New task
				table.insert(changes.created_tasks, {
					content = content,
					is_completed = is_completed,
					depth = depth,
					line = line_num,
				})
			end
		end
	end

	-- Find deleted items
	for _, mark in ipairs(extmarks) do
		local data = mark[4]
		if data and data.todoist_id and not seen_ids[data.todoist_id] then
			if data.todoist_type == "section" then
				table.insert(changes.deleted_sections, data.todoist_id)
			elseif data.todoist_type == "task" then
				table.insert(changes.deleted_tasks, data.todoist_id)
			end
		end
	end

	return changes
end

return M
