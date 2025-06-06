-- Parser for converting between Todoist data and markdown
local M = {}

local config = require("todoist.config")

-- Helper function to calculate effective indentation (treating tabs as spaces)
local function get_effective_indent(line)
	local indent_str = line:match("^(%s*)")
	local effective_indent = 0

	for i = 1, #indent_str do
		local char = indent_str:sub(i, i)
		if char == "\t" then
			-- Treat tab as 2 spaces (or 4, depending on your preference)
			effective_indent = effective_indent + 2
		elseif char == " " then
			effective_indent = effective_indent + 1
		end
	end

	return effective_indent, indent_str
end

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

	-- Separate unsectioned and sectioned tasks
	local unsectioned_tasks = {}
	local task_by_section = {}

	for _, task in ipairs(project_data.tasks or {}) do
		if config.is_valid(task) then
			if config.is_valid(task.section_id) then
				if not task_by_section[task.section_id] then
					task_by_section[task.section_id] = {}
				end
				table.insert(task_by_section[task.section_id], task)
			else
				table.insert(unsectioned_tasks, task)
			end
		end
	end

	-- Sort unsectioned tasks by order
	table.sort(unsectioned_tasks, function(a, b)
		local order_a = config.is_valid(a.order) and a.order or 999999
		local order_b = config.is_valid(b.order) and b.order or 999999
		return order_a < order_b
	end)

	-- Add unsectioned tasks first
	if #unsectioned_tasks > 0 then
		if config.is_debug() then
			print("DEBUG: Adding", #unsectioned_tasks, "unsectioned tasks first")
		end
		M.add_tasks_to_markdown(unsectioned_tasks, lines, extmarks, nil)
		table.insert(lines, "")
	end

	-- Sort sections by order
	local sections = {}
	for _, section in ipairs(project_data.sections or {}) do
		if config.is_valid(section) and config.is_valid(section.id) then
			local section_order = config.is_valid(section.order) and section.order or 999999
			table.insert(sections, {
				data = section,
				tasks = task_by_section[section.id] or {},
				order = section_order,
			})
		end
	end

	table.sort(sections, function(a, b)
		return a.order < b.order
	end)

	-- Add sections and their tasks
	for _, section_info in ipairs(sections) do
		local section = section_info.data
		local section_tasks = section_info.tasks

		if config.is_debug() then
			print("DEBUG: Adding section", section.name, "with", #section_tasks, "tasks, order:", section_info.order)
		end

		-- Add section header
		local section_name = config.is_valid(section.name) and section.name or "Untitled Section"
		table.insert(lines, "## " .. section_name)
		table.insert(extmarks, {
			line = #lines - 1,
			col = 0,
			opts = {
				right_gravity = false,
				hl_mode = "combine",
			},
			-- Store our custom data separately
			todoist_data = {
				type = "section",
				id = tostring(section.id),
				name = section_name,
			},
		})
		table.insert(lines, "")

		-- Add tasks for this section
		if #section_tasks > 0 then
			M.add_tasks_to_markdown(section_tasks, lines, extmarks, section.id)
			table.insert(lines, "")
		end
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

	-- Sort root tasks by order
	table.sort(root_tasks, function(a, b)
		local order_a = config.is_valid(a.order) and a.order or 999999
		local order_b = config.is_valid(b.order) and b.order or 999999
		return order_a < order_b
	end)

	-- Sort all child task groups by order
	for parent_id, children in pairs(task_children) do
		table.sort(children, function(a, b)
			local order_a = config.is_valid(a.order) and a.order or 999999
			local order_b = config.is_valid(b.order) and b.order or 999999
			return order_a < order_b
		end)
	end

	if config.is_debug() then
		print("DEBUG: Root tasks for section:", #root_tasks)
		for i, task in ipairs(root_tasks) do
			local content = config.is_valid(task.content) and task.content or "No content"
			local order = config.is_valid(task.order) and task.order or "no order"
			print("DEBUG: Root task", i, ":", content, "ID:", task.id, "order:", order)
		end
	end

	-- Add tasks recursively
	for _, task in ipairs(root_tasks) do
		M.add_single_task_to_markdown(task, lines, extmarks, 0, task_children)
	end
end

function M.add_single_task_to_markdown(task, lines, extmarks, depth, task_children)
	local indent = string.rep("  ", depth)
	local is_completed = config.is_valid(task.is_completed) and task.is_completed or false
	local checkbox = is_completed and "[x]" or "[ ]"
	local task_content = config.is_valid(task.content) and task.content or "No content"
	local task_description = config.is_valid(task.description) and task.description or ""
	local task_line = indent .. "- " .. checkbox .. " " .. task_content

	if config.is_debug() then
		print("DEBUG: Adding task line:", task_line, "ID:", task.id, "description:", task_description)
	end

	table.insert(lines, task_line)
	table.insert(extmarks, {
		line = #lines - 1,
		col = 0,
		opts = {
			right_gravity = false,
			hl_mode = "combine",
		},
		-- Store our custom data separately
		todoist_data = {
			type = "task",
			id = tostring(task.id),
			content = task_content,
			description = task_description,
			completed = is_completed,
			parent_id = config.is_valid(task.parent_id) and tostring(task.parent_id) or nil,
			section_id = config.is_valid(task.section_id) and tostring(task.section_id) or nil,
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

	-- Add children (already sorted)
	if config.is_valid(task.id) and task_children[task.id] then
		if config.is_debug() then
			print("DEBUG: Adding", #task_children[task.id], "children for task:", task_content)
		end

		for _, child in ipairs(task_children[task.id]) do
			M.add_single_task_to_markdown(child, lines, extmarks, depth + 1, task_children)
		end
	end
end

-- Backward compatibility - keep the old function name
function M.add_task_to_markdown(task, lines, extmarks, depth, task_children)
	return M.add_single_task_to_markdown(task, lines, extmarks, depth, task_children)
end

-- Global storage for extmark data (since we can't store custom data in extmarks directly)
local extmark_data_store = {}

function M.set_extmarks(buf, ns_id, extmarks)
	if config.is_debug() then
		print("DEBUG: Setting", #extmarks, "extmarks in buffer", buf)
	end

	-- Clear previous data for this buffer
	extmark_data_store[buf] = {}

	for i, mark in ipairs(extmarks) do
		local success, result = pcall(function()
			local mark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, mark.line, mark.col, mark.opts)

			-- Store our custom data separately, indexed by the extmark ID
			if mark.todoist_data then
				extmark_data_store[buf][mark_id] = mark.todoist_data

				if config.is_debug() then
					print(
						"DEBUG: Set extmark",
						i,
						"at line",
						mark.line,
						"with ID",
						mark_id,
						"type:",
						mark.todoist_data.type,
						"todoist_id:",
						mark.todoist_data.id
					)
				end
			end

			return mark_id
		end)

		if not success then
			if config.is_debug() then
				print("DEBUG: Failed to set extmark", i, "at line", mark.line, "error:", result)
			end
		end
	end

	-- Verify extmarks were set
	if config.is_debug() then
		vim.schedule(function()
			local test_extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
			print("DEBUG: Verification - found", #test_extmarks, "extmarks after setting")
			print("DEBUG: Stored data for", vim.tbl_count(extmark_data_store[buf] or {}), "extmarks")
		end)
	end
end

-- Get extmarks with their associated todoist data
function M.get_extmarks_with_data(buf, ns_id)
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
	local result = {}

	for _, mark in ipairs(extmarks) do
		local mark_id = mark[1]
		local line_num = mark[2]
		local col_num = mark[3]
		local opts = mark[4]

		-- Get our stored data
		local todoist_data = nil
		if extmark_data_store[buf] and extmark_data_store[buf][mark_id] then
			todoist_data = extmark_data_store[buf][mark_id]
		end

		table.insert(result, {
			mark_id,
			line_num,
			col_num,
			todoist_data, -- This replaces the opts[4] that we were trying to use before
		})
	end

	return result
end

-- Expose the extmark data store for external access
function M.get_extmark_data_store()
	return extmark_data_store
end

-- Update extmarks with newly created item IDs
function M.update_extmarks_with_created_items(buf, ns_id, created_items)
	if not created_items or vim.tbl_count(created_items) == 0 then
		return
	end

	if config.is_debug() then
		print("DEBUG: Updating extmarks with created items:", vim.inspect(created_items))
	end

	-- Initialize storage for this buffer if it doesn't exist
	if not extmark_data_store[buf] then
		extmark_data_store[buf] = {}
	end

	for line_num, item in pairs(created_items) do
		if config.is_valid(item) and config.is_valid(item.id) then
			local opts = {
				right_gravity = false,
				hl_mode = "combine",
			}

			local todoist_data = {
				type = item.type,
				id = tostring(item.id),
			}

			if item.type == "task" then
				todoist_data.content = item.content
				todoist_data.description = item.description or ""
				todoist_data.completed = item.is_completed or false
				todoist_data.parent_id = nil
				todoist_data.section_id = nil
			elseif item.type == "section" then
				todoist_data.name = item.name
			end

			local success, mark_id = pcall(function()
				return vim.api.nvim_buf_set_extmark(buf, ns_id, line_num, 0, opts)
			end)

			if success and mark_id then
				-- Store our custom data
				extmark_data_store[buf][mark_id] = todoist_data

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
			elseif config.is_debug() then
				print("DEBUG: Failed to update extmark for", item.type, "at line", line_num, "error:", mark_id)
			end
		end
	end
end

-- Parse task description from markdown lines following a task
function M.parse_task_description(lines, task_line_index, task_indent_level)
	local description_lines = {}
	local i = task_line_index + 1

	if config.is_debug() then
		print("DEBUG: Parsing description for task at line", task_line_index, "with indent level", task_indent_level)
		print("DEBUG: Total lines available:", #lines)
	end

	-- Skip empty line immediately after task (if it exists)
	if i <= #lines and lines[i] == "" then
		if config.is_debug() then
			print("DEBUG: Skipping empty line at", i)
		end
		i = i + 1
	end

	-- Parse description lines
	while i <= #lines do
		local line = lines[i]

		if config.is_debug() then
			print("DEBUG: Examining line", i, ":", line)
		end

		-- Stop if we hit another task or section
		if line:match("^%s*%-") or line:match("^#") then
			if config.is_debug() then
				print("DEBUG: Found another task/section at line", i, "stopping description parsing")
			end
			break
		end

		-- If we hit a non-empty line, check its effective indentation
		if line ~= "" then
			local line_effective_indent, line_indent_str = get_effective_indent(line)

			if config.is_debug() then
				print(
					"DEBUG: Line",
					i,
					"effective indent:",
					line_effective_indent,
					"vs task indent:",
					task_indent_level,
					"indent string:",
					vim.inspect(line_indent_str)
				)
			end

			-- Stop only if the line has LESS indentation than the task
			-- Lines at the same indentation level or higher should be included in the description
			if line_effective_indent < task_indent_level then
				if config.is_debug() then
					print(
						"DEBUG: Line",
						i,
						"has insufficient effective indent (",
						line_effective_indent,
						"vs",
						task_indent_level,
						"), stopping description parsing"
					)
				end
				break
			end
		end

		-- Add to description (remove appropriate indentation)
		if line == "" then
			table.insert(description_lines, "")
			if config.is_debug() then
				print("DEBUG: Added empty line to description")
			end
		else
			local expected_effective_indent = task_indent_level + 2
			local line_effective_indent, line_indent_str = get_effective_indent(line)

			if line_effective_indent >= expected_effective_indent then
				-- Calculate how much to remove (in characters, not effective spaces)
				local chars_to_remove = 0
				local effective_removed = 0

				for j = 1, #line_indent_str do
					local char = line_indent_str:sub(j, j)
					chars_to_remove = chars_to_remove + 1

					if char == "\t" then
						effective_removed = effective_removed + 2
					elseif char == " " then
						effective_removed = effective_removed + 1
					end

					if effective_removed >= expected_effective_indent then
						break
					end
				end

				local desc_line = line:sub(chars_to_remove + 1)
				table.insert(description_lines, desc_line)
				if config.is_debug() then
					print("DEBUG: Added description line (removed", chars_to_remove, "chars):", desc_line)
				end
			else
				-- Line has some indentation but less than expected
				-- Still include it but with minimal processing
				local desc_line = line:gsub("^%s*", "")
				table.insert(description_lines, desc_line)
				if config.is_debug() then
					print("DEBUG: Added less-indented description line:", desc_line)
				end
			end
		end

		i = i + 1
	end

	-- Remove trailing empty lines
	while #description_lines > 0 and description_lines[#description_lines] == "" do
		table.remove(description_lines)
		if config.is_debug() then
			print("DEBUG: Removed trailing empty line")
		end
	end

	local final_description = table.concat(description_lines, "\n")

	if config.is_debug() then
		print("DEBUG: Final description:", final_description)
		print("DEBUG: Stopped parsing at line", i - 1)
	end

	return final_description, i - 1
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
	end

	-- Create lookup tables
	local extmark_by_line = {}
	local existing_ids = {}

	-- Build extmark lookup by line number and collect existing IDs
	for _, mark in ipairs(extmarks) do
		local line_num = mark[2]
		local data = mark[4] -- This is now our todoist_data

		if config.is_valid(data) and config.is_valid(data.id) then
			extmark_by_line[line_num] = data
			existing_ids[data.id] = true

			if config.is_debug() then
				print("DEBUG: Found extmark at line", line_num, "for", data.type, "ID:", data.id)
			end
		end
	end

	if config.is_debug() then
		print("DEBUG: Total existing IDs:", vim.tbl_count(existing_ids))
		print("DEBUG: Existing IDs:", vim.inspect(vim.tbl_keys(existing_ids)))
	end

	local seen_ids = {}
	local i = 1

	-- Parse lines and detect changes
	while i <= #lines do
		local line = lines[i]
		local line_num = i - 1

		if config.is_debug() then
			print("DEBUG: Processing line", i, ":", line)
		end

		-- Check for section headers
		local section_title = line:match("^## (.+)$")
		if config.is_valid(section_title) then
			local extmark_data = extmark_by_line[line_num]

			if config.is_valid(extmark_data) and extmark_data.type == "section" then
				-- Existing section - check for updates
				seen_ids[extmark_data.id] = true

				-- Check if name changed
				if extmark_data.name ~= section_title then
					table.insert(changes.updated_sections, {
						id = extmark_data.id,
						name = section_title,
					})
					if config.is_debug() then
						print(
							"DEBUG: Section updated:",
							extmark_data.id,
							"from",
							extmark_data.name,
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
			i = i + 1
		else
			-- Check for tasks
			local indent_str, checkbox, content = line:match("^(%s*)%- %[([%sx])%] (.+)$")
			if config.is_valid(content) then
				local task_effective_indent, _ = get_effective_indent(line)
				local depth = math.floor(task_effective_indent / 2)
				local is_completed = checkbox == "x"

				if config.is_debug() then
					print(
						"DEBUG: Found task:",
						content,
						"at line",
						i,
						"with effective indent",
						task_effective_indent,
						"depth:",
						depth,
						"indent string:",
						vim.inspect(indent_str)
					)
				end

				-- Parse task description (use effective indentation)
				local description, last_desc_line = M.parse_task_description(lines, i, task_effective_indent)

				local extmark_data = extmark_by_line[line_num]

				if config.is_valid(extmark_data) and extmark_data.type == "task" then
					-- Existing task - check for updates
					seen_ids[extmark_data.id] = true

					-- Check if content, completion status, or description changed
					local content_changed = extmark_data.content ~= content
					local completion_changed = extmark_data.completed ~= is_completed
					local description_changed = (extmark_data.description or "") ~= description

					if content_changed or completion_changed or description_changed then
						table.insert(changes.updated_tasks, {
							id = extmark_data.id,
							content = content,
							description = description,
							is_completed = is_completed,
						})
						if config.is_debug() then
							print("DEBUG: Task updated:", extmark_data.id)
							if content_changed then
								print("  Content changed from:", extmark_data.content, "to:", content)
							end
							if completion_changed then
								print("  Completion changed from:", extmark_data.completed, "to:", is_completed)
							end
							if description_changed then
								print("  Description changed from:", extmark_data.description or "", "to:", description)
							end
						end
					end
				else
					-- New task
					table.insert(changes.created_tasks, {
						content = content,
						description = description,
						is_completed = is_completed,
						depth = depth,
						line = line_num,
					})
					if config.is_debug() then
						print(
							"DEBUG: New task created:",
							content,
							"at line",
							line_num,
							"depth:",
							depth,
							"with description:",
							description
						)
					end
				end

				-- Skip to after the description
				i = last_desc_line + 1
				if config.is_debug() then
					print("DEBUG: Continuing parsing from line", i)
				end
			else
				i = i + 1
			end
		end
	end

	-- Find deleted items (existed in extmarks but not seen in current content)
	for _, mark in ipairs(extmarks) do
		local data = mark[4] -- This is now our todoist_data
		if config.is_valid(data) and config.is_valid(data.id) and not seen_ids[data.id] then
			if data.type == "section" then
				table.insert(changes.deleted_sections, data.id)
				if config.is_debug() then
					print("DEBUG: Section deleted:", data.id)
				end
			elseif data.type == "task" then
				table.insert(changes.deleted_tasks, data.id)
				if config.is_debug() then
					print("DEBUG: Task deleted:", data.id)
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
