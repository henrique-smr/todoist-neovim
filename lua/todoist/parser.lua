-- Parser for converting between Todoist data and markdown
local M = {}

local config = require("todoist.config")

function M.project_to_markdown(project_data)
	local lines = {}
	local extmarks = {}

	-- Add project title
	local project_name = "Untitled Project"
	if config.is_valid(project_data.project) and config.is_valid(project_data.project.name) then
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
		if config.is_valid(section) and config.is_valid(section.id) then
			section_lookup[section.id] = section
			sections[section.id] = {
				section = section,
				tasks = {},
			}
		end
	end

	-- Group tasks
	for _, task in ipairs(project_data.tasks or {}) do
		if config.is_debug() then
			print("DEBUG: Processing task:", vim.inspect(task))
		end

		if config.is_valid(task) then
			if config.is_valid(task.section_id) and sections[task.section_id] then
				table.insert(sections[task.section_id].tasks, task)
			else
				table.insert(unsectioned_tasks, task)
			end
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
			local section_name = config.is_valid(section_data.section.name) and section_data.section.name
				or "Untitled Section"
			table.insert(lines, "## " .. section_name)
			table.insert(extmarks, {
				line = #lines - 1,
				col = 0,
				opts = {
					end_line = #lines - 1,
					end_col = -1,
					todoist_type = "section",
					todoist_id = tostring(section_data.section.id),
					todoist_name = section_name,
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
		if config.is_valid(task) and config.is_valid(task.id) then
			if config.is_valid(task.parent_id) then
				if not task_children[task.parent_id] then
					task_children[task.parent_id] = {}
				end
				table.insert(task_children[task.parent_id], task)
			else
				table.insert(root_tasks, task)
			end
		end
	end

	-- Sort tasks by order if available
	table.sort(root_tasks, function(a, b)
		local order_a = config.is_valid(a.order) and a.order or 0
		local order_b = config.is_valid(b.order) and b.order or 0
		return order_a < order_b
	end)

	if config.is_debug() then
		print("DEBUG: Root tasks for section:", #root_tasks)
		for i, task in ipairs(root_tasks) do
			local content = config.is_valid(task.content) and task.content or "No content"
			print("DEBUG: Root task", i, ":", content, "ID:", task.id)
		end
	end

	-- Add tasks recursively
	for _, task in ipairs(root_tasks) do
		M.add_task_to_markdown(task, lines, extmarks, 0, task_children)
	end
end

function M.add_task_to_markdown(task, lines, extmarks, depth, task_children)
	local indent = string.rep("  ", depth)
	local is_completed = config.is_valid(task.is_completed) and task.is_completed or false
	local checkbox = is_completed and "[x]" or "[ ]"
	local task_content = config.is_valid(task.content) and task.content or "No content"
	local task_line = indent .. "- " .. checkbox .. " " .. task_content

	if config.is_debug() then
		print("DEBUG: Adding task line:", task_line, "ID:", task.id)
	end

	table.insert(lines, task_line)
	table.insert(extmarks, {
		line = #lines - 1,
		col = 0,
		opts = {
			end_line = #lines - 1,
			end_col = -1,
			todoist_type = "task",
			todoist_id = tostring(task.id),
			todoist_content = task_content,
			todoist_completed = is_completed,
			parent_id = config.is_valid(task.parent_id) and tostring(task.parent_id) or vim.NIL,
			section_id = config.is_valid(task.section_id) and tostring(task.section_id) or vim.NIL,
		},
	})

	-- Add description if exists
	if config.is_valid(task.description) and task.description ~= "" then
		table.insert(lines, "")
		local desc_lines = vim.split(task.description, "\n")
		for _, desc_line in ipairs(desc_lines) do
			table.insert(lines, indent .. "  " .. desc_line)
		end
		table.insert(lines, "")
	end

	-- Add children
	if config.is_valid(task.id) and task_children[task.id] then
		-- Sort children by order
		table.sort(task_children[task.id], function(a, b)
			local order_a = config.is_valid(a.order) and a.order or 0
			local order_b = config.is_valid(b.order) and b.order or 0
			return order_a < order_b
		end)

		if config.is_debug() then
			print("DEBUG: Adding", #task_children[task.id], "children for task:", task_content)
		end

		for _, child in ipairs(task_children[task.id]) do
			M.add_task_to_markdown(child, lines, extmarks, depth + 1, task_children)
		end
	end
end

function M.set_extmarks(buf, ns_id, extmarks)
	if config.is_debug() then
		print("DEBUG: Setting", #extmarks, "extmarks in buffer", buf)
	end

	for i, mark in ipairs(extmarks) do
		local success, err = pcall(function()
			local mark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, mark.line, mark.col, mark.opts)
			if config.is_debug() then
				print(
					"DEBUG: Set extmark",
					i,
					"at line",
					mark.line,
					"with ID",
					mark_id,
					"type:",
					mark.opts.todoist_type
				)
			end
		end)

		if not success and config.is_debug() then
			print("DEBUG: Error:", err)
			print("DEBUG: Failed to set extmark", i, "at line", mark.line)
		end
	end

	-- Verify extmarks were set
	if config.is_debug() then
		vim.schedule(function()
			local test_extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
			print("DEBUG: Verification - found", #test_extmarks, "extmarks after setting")
		end)
	end
end

-- Update extmarks with newly created item IDs
function M.update_extmarks_with_created_items(buf, ns_id, created_items)
	if not created_items or vim.tbl_count(created_items) == 0 then
		return
	end

	if config.is_debug() then
		print("DEBUG: Updating extmarks with created items:", vim.inspect(created_items))
	end

	for line_num, item in pairs(created_items) do
		if config.is_valid(item) and config.is_valid(item.id) then
			local opts = {
				end_line = line_num,
				end_col = -1,
				todoist_type = item.type,
				todoist_id = tostring(item.id),
			}

			if item.type == "task" then
				opts.todoist_content = item.content
				opts.todoist_completed = item.is_completed or false
				opts.parent_id = vim.NIL
				opts.section_id = vim.NIL
			elseif item.type == "section" then
				opts.todoist_name = item.name
			end

			local success = pcall(function()
				local mark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, line_num, 0, opts)
				if config.is_debug() then
					print(
						"DEBUG: Updated extmark for",
						item.type,
						"at line",
						line_num,
						"with ID",
						item.id,
						"mark_id:",
						mark_id
					)
				end
			end)

			if not success and config.is_debug() then
				print("DEBUG: Failed to update extmark for", item.type, "at line", line_num)
			end
		end
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

	if config.is_debug() then
		print("DEBUG: Parsing changes from", #lines, "lines and", #extmarks, "extmarks")
		for i, mark in ipairs(extmarks) do
			if i <= 5 then -- Only show first 5 to avoid spam
				print("DEBUG: Extmark", i, ":", vim.inspect(mark))
			end
		end
	end

	-- Create lookup tables
	local extmark_by_line = {}
	local existing_ids = {}

	-- Build extmark lookup by line number and collect existing IDs
	for _, mark in ipairs(extmarks) do
		local line_num = mark[2]
		local data = mark[4]

		if config.is_valid(data) and config.is_valid(data.todoist_id) then
			extmark_by_line[line_num] = data
			existing_ids[data.todoist_id] = true

			if config.is_debug() then
				print("DEBUG: Found extmark at line", line_num, "for", data.todoist_type, "ID:", data.todoist_id)
			end
		end
	end

	if config.is_debug() then
		print("DEBUG: Total existing IDs:", vim.tbl_count(existing_ids))
		print("DEBUG: Existing IDs:", vim.inspect(vim.tbl_keys(existing_ids)))
	end

	local seen_ids = {}

	-- Parse lines and detect changes
	for i, line in ipairs(lines) do
		local line_num = i - 1

		-- Check for section headers
		local section_title = line:match("^## (.+)$")
		if config.is_valid(section_title) then
			local extmark_data = extmark_by_line[line_num]

			if config.is_valid(extmark_data) and extmark_data.todoist_type == "section" then
				-- Existing section - check for updates
				seen_ids[extmark_data.todoist_id] = true

				-- Check if name changed
				if extmark_data.todoist_name ~= section_title then
					table.insert(changes.updated_sections, {
						id = extmark_data.todoist_id,
						name = section_title,
					})
					if config.is_debug() then
						print(
							"DEBUG: Section updated:",
							extmark_data.todoist_id,
							"from",
							extmark_data.todoist_name,
							"to",
							section_title
						)
					end
				end
			else
				-- New section
				table.insert(changes.created_sections, {
					name = section_title,
					line = line_num,
				})
				if config.is_debug() then
					print("DEBUG: New section created:", section_title, "at line", line_num)
				end
			end
		end

		-- Check for tasks
		local indent, checkbox, content = line:match("^(%s*)%- %[([%sx])%] (.+)$")
		if config.is_valid(content) then
			local depth = math.floor(#indent / 2)
			local is_completed = checkbox == "x"

			local extmark_data = extmark_by_line[line_num]

			if config.is_valid(extmark_data) and extmark_data.todoist_type == "task" then
				-- Existing task - check for updates
				seen_ids[extmark_data.todoist_id] = true

				-- Check if content or completion status changed
				local content_changed = extmark_data.todoist_content ~= content
				local completion_changed = extmark_data.todoist_completed ~= is_completed

				if content_changed or completion_changed then
					table.insert(changes.updated_tasks, {
						id = extmark_data.todoist_id,
						content = content,
						is_completed = is_completed,
					})
					if config.is_debug() then
						print("DEBUG: Task updated:", extmark_data.todoist_id)
						if content_changed then
							print("  Content changed from:", extmark_data.todoist_content, "to:", content)
						end
						if completion_changed then
							print("  Completion changed from:", extmark_data.todoist_completed, "to:", is_completed)
						end
					end
				end
			else
				-- New task
				table.insert(changes.created_tasks, {
					content = content,
					is_completed = is_completed,
					depth = depth,
					line = line_num,
				})
				if config.is_debug() then
					print("DEBUG: New task created:", content, "at line", line_num)
				end
			end
		end
	end

	-- Find deleted items (existed in extmarks but not seen in current content)
	for _, mark in ipairs(extmarks) do
		local data = mark[4]
		if config.is_valid(data) and config.is_valid(data.todoist_id) and not seen_ids[data.todoist_id] then
			if data.todoist_type == "section" then
				table.insert(changes.deleted_sections, data.todoist_id)
				if config.is_debug() then
					print("DEBUG: Section deleted:", data.todoist_id)
				end
			elseif data.todoist_type == "task" then
				table.insert(changes.deleted_tasks, data.todoist_id)
				if config.is_debug() then
					print("DEBUG: Task deleted:", data.todoist_id)
				end
			end
		end
	end

	if config.is_debug() then
		print("DEBUG: Changes summary:")
		print("  Created sections:", #changes.created_sections)
		print("  Updated sections:", #changes.updated_sections)
		print("  Deleted sections:", #changes.deleted_sections)
		print("  Created tasks:", #changes.created_tasks)
		print("  Updated tasks:", #changes.updated_tasks)
		print("  Deleted tasks:", #changes.deleted_tasks)
	end

	return changes
end

return M

