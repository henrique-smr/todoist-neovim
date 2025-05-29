-- Sync engine for bidirectional synchronization
local M = {}

local api = require("todoist.api")
local parser = require("todoist.parser")
local config = require("todoist.config")

function M.sync_buffer_changes(project_id, lines, extmarks, callback)
	if config.is_debug() then
		print("DEBUG: Starting bidirectional sync for project:", project_id)
	end

	-- Step 1: Get current state from Todoist
	api.get_project_data(project_id, function(remote_result)
		if remote_result.error then
			callback(remote_result)
			return
		end

		if config.is_debug() then
			print(
				"DEBUG: Fetched remote data - tasks:",
				#(remote_result.data.tasks or {}),
				"sections:",
				#(remote_result.data.sections or {})
			)
		end

		-- Step 2: Parse local changes
		local local_changes = parser.parse_markdown_to_changes(lines, extmarks)

		if config.is_debug() then
			print("DEBUG: Local changes:", vim.inspect(local_changes))
		end

		-- Step 3: Detect remote changes by comparing with extmarks
		local remote_changes = M.detect_remote_changes(remote_result.data, extmarks)

		if config.is_debug() then
			print("DEBUG: Remote changes:", vim.inspect(remote_changes))
		end

		-- Step 4: Merge and resolve conflicts
		local merged_changes = M.merge_changes(local_changes, remote_changes, remote_result.data)

		if config.is_debug() then
			print("DEBUG: Merged changes:", vim.inspect(merged_changes))
		end

		-- Step 5: Apply changes
		M.execute_sync_operations(project_id, merged_changes, lines, extmarks, function(sync_result)
			if sync_result.error then
				callback(sync_result)
				return
			end

			-- Step 6: Always fetch final state for rendering
			if config.is_debug() then
				print("DEBUG: Fetching final project state after sync")
			end

			api.get_project_data(project_id, function(final_result)
				if final_result.error then
					callback(final_result)
					return
				end

				if config.is_debug() then
					print(
						"DEBUG: Final fetch complete - tasks:",
						#(final_result.data.tasks or {}),
						"sections:",
						#(final_result.data.sections or {})
					)
				end

				callback({
					data = {
						success = true,
						project_data = final_result.data,
						created_items = sync_result.data.created_items or {},
					},
				})
			end)
		end)
	end)
end

-- Detect changes made remotely (in Todoist web/app) since last sync
function M.detect_remote_changes(remote_data, extmarks)
	local changes = {
		remote_updates = {},
		remote_creates = {},
		remote_deletes = {},
	}

	-- Build lookup of local items from extmarks
	local local_items = {}
	for _, mark in ipairs(extmarks) do
		local data = mark[4]
		if config.is_valid(data) and config.is_valid(data.id) then
			local_items[data.id] = data
		end
	end

	if config.is_debug() then
		print("DEBUG: Local items from extmarks:", vim.tbl_count(local_items))
		print("DEBUG: Local item IDs:", vim.inspect(vim.tbl_keys(local_items)))
	end

	-- Check remote tasks for changes/additions
	for _, remote_task in ipairs(remote_data.tasks or {}) do
		if config.is_valid(remote_task) and config.is_valid(remote_task.id) then
			local task_id = tostring(remote_task.id)
			local local_task = local_items[task_id]

			if local_task then
				-- Task exists locally - check for remote updates
				local content_changed = local_task.content ~= (remote_task.content or "")
				local description_changed = (local_task.description or "") ~= (remote_task.description or "")
				local completion_changed = local_task.completed ~= (remote_task.is_completed or false)

				if content_changed or description_changed or completion_changed then
					table.insert(changes.remote_updates, {
						type = "task",
						id = task_id,
						remote_data = remote_task,
						local_data = local_task,
					})

					if config.is_debug() then
						print("DEBUG: Remote task update detected:", task_id)
						if content_changed then
							print(
								"  Content: local='"
									.. (local_task.content or "")
									.. "' remote='"
									.. (remote_task.content or "")
									.. "'"
							)
						end
						if description_changed then
							print(
								"  Description: local='"
									.. (local_task.description or "")
									.. "' remote='"
									.. (remote_task.description or "")
									.. "'"
							)
						end
						if completion_changed then
							print(
								"  Completion: local="
									.. tostring(local_task.completed)
									.. " remote="
									.. tostring(remote_task.is_completed or false)
							)
						end
					end
				end
			else
				-- Task doesn't exist locally - remote addition
				table.insert(changes.remote_creates, {
					type = "task",
					data = remote_task,
				})

				if config.is_debug() then
					print("DEBUG: Remote task creation detected:", task_id, remote_task.content)
				end
			end
		end
	end

	-- Check remote sections for changes/additions
	for _, remote_section in ipairs(remote_data.sections or {}) do
		if config.is_valid(remote_section) and config.is_valid(remote_section.id) then
			local section_id = tostring(remote_section.id)
			local local_section = local_items[section_id]

			if local_section then
				-- Section exists locally - check for remote updates
				if local_section.name ~= (remote_section.name or "") then
					table.insert(changes.remote_updates, {
						type = "section",
						id = section_id,
						remote_data = remote_section,
						local_data = local_section,
					})

					if config.is_debug() then
						print("DEBUG: Remote section update detected:", section_id)
						print(
							"  Name: local='"
								.. (local_section.name or "")
								.. "' remote='"
								.. (remote_section.name or "")
								.. "'"
						)
					end
				end
			else
				-- Section doesn't exist locally - remote addition
				table.insert(changes.remote_creates, {
					type = "section",
					data = remote_section,
				})

				if config.is_debug() then
					print("DEBUG: Remote section creation detected:", section_id, remote_section.name)
				end
			end
		end
	end

	-- Check for remote deletions (local items not in remote)
	local remote_items = {}
	for _, task in ipairs(remote_data.tasks or {}) do
		if config.is_valid(task) and config.is_valid(task.id) then
			remote_items[tostring(task.id)] = true
		end
	end
	for _, section in ipairs(remote_data.sections or {}) do
		if config.is_valid(section) and config.is_valid(section.id) then
			remote_items[tostring(section.id)] = true
		end
	end

	for item_id, local_data in pairs(local_items) do
		if not remote_items[item_id] then
			table.insert(changes.remote_deletes, {
				type = local_data.type,
				id = item_id,
				local_data = local_data,
			})

			if config.is_debug() then
				print("DEBUG: Remote deletion detected:", item_id, local_data.type)
			end
		end
	end

	return changes
end

-- Merge local and remote changes, resolving conflicts
function M.merge_changes(local_changes, remote_changes, remote_data)
	local merged = {
		created_sections = {},
		updated_sections = {},
		deleted_sections = {},
		created_tasks = {},
		updated_tasks = {},
		deleted_tasks = {},
		accept_remote_updates = {},
		accept_remote_creates = {},
		accept_remote_deletes = {},
	}

	-- Build lookup of local changes by ID
	local local_updates_by_id = {}
	local local_deletes_by_id = {}

	for _, update in ipairs(local_changes.updated_tasks) do
		if config.is_valid(update.id) then
			local_updates_by_id[update.id] = update
		end
	end
	for _, update in ipairs(local_changes.updated_sections) do
		if config.is_valid(update.id) then
			local_updates_by_id[update.id] = update
		end
	end
	for _, delete_id in ipairs(local_changes.deleted_tasks) do
		local_deletes_by_id[delete_id] = "task"
	end
	for _, delete_id in ipairs(local_changes.deleted_sections) do
		local_deletes_by_id[delete_id] = "section"
	end

	-- Handle remote updates with conflict resolution
	for _, remote_update in ipairs(remote_changes.remote_updates) do
		local item_id = remote_update.id
		local local_update = local_updates_by_id[item_id]
		local local_delete = local_deletes_by_id[item_id]

		if local_delete then
			-- Conflict: local delete vs remote update
			-- Resolution: Prefer local delete (user intention)
			if remote_update.type == "task" then
				table.insert(merged.deleted_tasks, item_id)
			else
				table.insert(merged.deleted_sections, item_id)
			end

			if config.is_debug() then
				print("DEBUG: Conflict resolved - local delete wins over remote update:", item_id)
			end
		elseif local_update then
			-- Conflict: local update vs remote update
			-- Resolution: Prefer local update (user intention)
			if remote_update.type == "task" then
				table.insert(merged.updated_tasks, local_update)
			else
				table.insert(merged.updated_sections, local_update)
			end

			if config.is_debug() then
				print("DEBUG: Conflict resolved - local update wins over remote update:", item_id)
			end
		else
			-- No conflict: accept remote update
			table.insert(merged.accept_remote_updates, remote_update)

			if config.is_debug() then
				print("DEBUG: Accepting remote update:", item_id)
			end
		end
	end

	-- Handle remote creates (no conflicts possible)
	for _, remote_create in ipairs(remote_changes.remote_creates) do
		table.insert(merged.accept_remote_creates, remote_create)

		if config.is_debug() then
			print("DEBUG: Accepting remote create:", remote_create.data.id or "no-id")
		end
	end

	-- Handle remote deletes with conflict resolution
	for _, remote_delete in ipairs(remote_changes.remote_deletes) do
		local item_id = remote_delete.id
		local local_update = local_updates_by_id[item_id]

		if local_update then
			-- Conflict: local update vs remote delete
			-- Resolution: Prefer local update (recreate item)
			if remote_delete.type == "task" then
				table.insert(merged.created_tasks, {
					content = local_update.content,
					description = local_update.description or "",
					is_completed = local_update.is_completed or false,
					depth = 0, -- Will be determined by sync logic
					line = -1, -- Will be determined by sync logic
				})
			else
				table.insert(merged.created_sections, {
					name = local_update.name,
					line = -1, -- Will be determined by sync logic
				})
			end

			if config.is_debug() then
				print("DEBUG: Conflict resolved - local update wins over remote delete, recreating:", item_id)
			end
		else
			-- No conflict: accept remote delete
			table.insert(merged.accept_remote_deletes, remote_delete)

			if config.is_debug() then
				print("DEBUG: Accepting remote delete:", item_id)
			end
		end
	end

	-- Add local-only changes (creates, updates, deletes without conflicts)
	for _, create in ipairs(local_changes.created_sections) do
		table.insert(merged.created_sections, create)
	end
	for _, create in ipairs(local_changes.created_tasks) do
		table.insert(merged.created_tasks, create)
	end

	-- Add updates and deletes that weren't conflicted
	for _, update in ipairs(local_changes.updated_tasks) do
		if config.is_valid(update.id) then
			local found_conflict = false
			for _, remote_update in ipairs(remote_changes.remote_updates) do
				if remote_update.id == update.id then
					found_conflict = true
					break
				end
			end
			for _, remote_delete in ipairs(remote_changes.remote_deletes) do
				if remote_delete.id == update.id then
					found_conflict = true
					break
				end
			end
			if not found_conflict then
				table.insert(merged.updated_tasks, update)
			end
		end
	end

	for _, update in ipairs(local_changes.updated_sections) do
		if config.is_valid(update.id) then
			local found_conflict = false
			for _, remote_update in ipairs(remote_changes.remote_updates) do
				if remote_update.id == update.id then
					found_conflict = true
					break
				end
			end
			for _, remote_delete in ipairs(remote_changes.remote_deletes) do
				if remote_delete.id == update.id then
					found_conflict = true
					break
				end
			end
			if not found_conflict then
				table.insert(merged.updated_sections, update)
			end
		end
	end

	for _, delete_id in ipairs(local_changes.deleted_tasks) do
		local found_conflict = false
		for _, remote_update in ipairs(remote_changes.remote_updates) do
			if remote_update.id == delete_id then
				found_conflict = true
				break
			end
		end
		if not found_conflict then
			table.insert(merged.deleted_tasks, delete_id)
		end
	end

	for _, delete_id in ipairs(local_changes.deleted_sections) do
		local found_conflict = false
		for _, remote_update in ipairs(remote_changes.remote_updates) do
			if remote_update.id == delete_id then
				found_conflict = true
				break
			end
		end
		if not found_conflict then
			table.insert(merged.deleted_sections, delete_id)
		end
	end

	return merged
end

function M.execute_sync_operations(project_id, changes, lines, extmarks, callback)
	local operations = {}
	local created_items = {} -- Track items created during sync
	local section_id_mappings = {} -- Map line numbers to section IDs
	local task_id_mappings = {} -- Map line numbers to task IDs

	-- Build extmark lookup for existing sections
	local existing_sections_by_line = {}
	for _, mark in ipairs(extmarks) do
		local line_num = mark[2]
		local data = mark[4]
		if config.is_valid(data) and data.type == "section" then
			existing_sections_by_line[line_num] = data.id
			if config.is_debug() then
				print("DEBUG: Found existing section at line", line_num, "ID:", data.id)
			end
		end
	end

	-- Note: Remote changes are already reflected in the final project data fetch
	-- We only need to apply local changes here

	-- Delete operations first
	for _, task_id in ipairs(changes.deleted_tasks) do
		if config.is_valid(task_id) then
			table.insert(operations, function(cb)
				if config.is_debug() then
					print("DEBUG: Deleting task:", task_id)
				end
				api.delete_task(task_id, cb)
			end)
		end
	end

	for _, section_id in ipairs(changes.deleted_sections) do
		if config.is_valid(section_id) then
			table.insert(operations, function(cb)
				if config.is_debug() then
					print("DEBUG: Deleting section:", section_id)
				end
				api.delete_section(section_id, cb)
			end)
		end
	end

	-- Update operations
	for _, task in ipairs(changes.updated_tasks) do
		if config.is_valid(task) and config.is_valid(task.id) and config.is_valid(task.content) then
			table.insert(operations, function(cb)
				if config.is_debug() then
					print(
						"DEBUG: Updating task:",
						task.id,
						"content:",
						task.content,
						"description:",
						task.description,
						"completed:",
						task.is_completed
					)
				end

				-- First get the current task state to avoid redundant operations
				api.get_task(task.id, function(get_result)
					if get_result.error then
						if config.is_debug() then
							print("DEBUG: Failed to get current task state:", get_result.error)
						end
						cb(get_result)
						return
					end

					local current_task = get_result.data
					local content_needs_update = current_task.content ~= task.content
					local description_needs_update = (current_task.description or "") ~= (task.description or "")
					local completion_needs_toggle = current_task.is_completed ~= task.is_completed

					if config.is_debug() then
						print(
							"DEBUG: Current task state - content:",
							current_task.content,
							"description:",
							current_task.description or "",
							"completed:",
							current_task.is_completed
						)
						print(
							"DEBUG: Desired task state - content:",
							task.content,
							"description:",
							task.description or "",
							"completed:",
							task.is_completed
						)
						print(
							"DEBUG: Needs content update:",
							content_needs_update,
							"needs description update:",
							description_needs_update,
							"needs completion toggle:",
							completion_needs_toggle
						)
					end

					-- Update content/description if needed
					if content_needs_update or description_needs_update then
						api.update_task(task.id, task.content, task.description, function(update_result)
							if update_result.error then
								cb(update_result)
								return
							end

							-- Then handle completion status if needed
							if completion_needs_toggle then
								api.toggle_task(task.id, task.is_completed, cb)
							else
								cb(update_result)
							end
						end)
					elseif completion_needs_toggle then
						-- Only toggle completion if content/description doesn't need updating
						api.toggle_task(task.id, task.is_completed, cb)
					else
						-- No changes needed
						if config.is_debug() then
							print("DEBUG: No changes needed for task:", task.id)
						end
						cb({ data = {} })
					end
				end)
			end)
		end
	end

	for _, section in ipairs(changes.updated_sections) do
		if config.is_valid(section) and config.is_valid(section.id) and config.is_valid(section.name) then
			table.insert(operations, function(cb)
				if config.is_debug() then
					print("DEBUG: Updating section:", section.id, "name:", section.name)
				end
				api.update_section(section.id, section.name, cb)
			end)
		end
	end

	-- Create sections first and track their IDs
	for _, section in ipairs(changes.created_sections) do
		if config.is_valid(section) and config.is_valid(section.name) then
			table.insert(operations, function(cb)
				if config.is_debug() then
					print("DEBUG: Creating section:", section.name, "at line:", section.line)
				end
				api.create_section(project_id, section.name, function(result)
					if not result.error and result.data and result.data.id then
						-- Track the created section
						created_items[section.line] = {
							type = "section",
							id = tostring(result.data.id),
							name = section.name,
						}
						-- Map section line to section ID for task creation
						section_id_mappings[section.line] = tostring(result.data.id)
						if config.is_debug() then
							print("DEBUG: Section created with ID:", result.data.id, "at line:", section.line)
						end
					end
					cb(result)
				end)
			end)
		end
	end

	-- Helper function to find the section for a task
	local function find_section_for_task(task_line, lines)
		-- Look backwards from the task line to find the most recent section
		for i = task_line, 1, -1 do
			local line = lines[i]
			if line and line:match("^## (.+)$") then
				if config.is_debug() then
					print("DEBUG: Found section at line", i, "for task at line", task_line)
				end

				-- Check if this section was newly created
				if section_id_mappings[i - 1] then -- -1 because line numbers are 0-indexed
					if config.is_debug() then
						print("DEBUG: Using newly created section ID:", section_id_mappings[i - 1])
					end
					return section_id_mappings[i - 1]
				end

				-- Check if this is an existing section
				if existing_sections_by_line[i - 1] then -- -1 because line numbers are 0-indexed
					if config.is_debug() then
						print("DEBUG: Using existing section ID:", existing_sections_by_line[i - 1])
					end
					return existing_sections_by_line[i - 1]
				end

				break
			end
		end
		return nil
	end

	-- Helper function to find the parent task for a subtask
	local function find_parent_for_task(task_line, task_depth, lines, created_tasks_by_line, existing_tasks_by_line)
		if task_depth == 0 then
			return nil -- Root task
		end

		local target_depth = task_depth - 1

		-- Look backwards from the task line to find a task at the target depth
		for i = task_line, 1, -1 do
			local line = lines[i]
			if line and line:match("^(%s*)%- %[([%sx])%] (.+)$") then
				local indent_str = line:match("^(%s*)")
				local line_depth = M.calculate_effective_depth(indent_str)

				if line_depth == target_depth then
					if config.is_debug() then
						print(
							"DEBUG: Found potential parent at line",
							i,
							"depth",
							line_depth,
							"for task at line",
							task_line,
							"depth",
							task_depth
						)
					end

					-- Check if this parent was newly created in this sync
					if created_tasks_by_line[i - 1] then -- -1 because line numbers are 0-indexed
						if config.is_debug() then
							print("DEBUG: Using newly created parent ID:", created_tasks_by_line[i - 1])
						end
						return created_tasks_by_line[i - 1]
					end

					-- Check if this is an existing task
					if existing_tasks_by_line[i - 1] then -- -1 because line numbers are 0-indexed
						if config.is_debug() then
							print("DEBUG: Using existing parent ID:", existing_tasks_by_line[i - 1])
						end
						return existing_tasks_by_line[i - 1]
					end

					break
				end
			end
		end
		return nil
	end

	-- Build extmark lookup for existing tasks
	local existing_tasks_by_line = {}
	for _, mark in ipairs(extmarks) do
		local line_num = mark[2]
		local data = mark[4]
		if config.is_valid(data) and data.type == "task" then
			existing_tasks_by_line[line_num] = data.id
			if config.is_debug() then
				print("DEBUG: Found existing task at line", line_num, "ID:", data.id)
			end
		end
	end

	-- Sort created tasks by depth (parents first, then children)
	table.sort(changes.created_tasks, function(a, b)
		return a.depth < b.depth
	end)

	-- Create tasks with proper hierarchy (parents first)
	local created_tasks_by_line = {}

	for _, task in ipairs(changes.created_tasks) do
		if config.is_valid(task) and config.is_valid(task.content) then
			table.insert(operations, function(cb)
				-- Determine section ID for this task
				local section_id = find_section_for_task(task.line, lines)

				-- Determine parent ID for this task
				local parent_id =
					find_parent_for_task(task.line, task.depth, lines, created_tasks_by_line, existing_tasks_by_line)

				if config.is_debug() then
					print("DEBUG: Creating task:", task.content, "at line:", task.line, "depth:", task.depth)
					print("  section_id:", section_id or "none", "parent_id:", parent_id or "none")
					print("  description:", task.description or "none")
				end

				api.create_task(project_id, task.content, section_id, parent_id, task.description, function(result)
					if not result.error and result.data and result.data.id then
						local task_id = tostring(result.data.id)

						-- Track the created task
						created_items[task.line] = {
							type = "task",
							id = task_id,
							content = task.content,
							description = task.description or "",
							is_completed = task.is_completed or false,
						}

						-- Map task line to task ID for child task creation
						created_tasks_by_line[task.line] = task_id

						if config.is_debug() then
							print(
								"DEBUG: Task created with ID:",
								task_id,
								"section_id:",
								section_id or "none",
								"parent_id:",
								parent_id or "none"
							)
						end
					end
					cb(result)
				end)
			end)
		end
	end

	if config.is_debug() then
		print("DEBUG: Executing", #operations, "sync operations")
	end

	-- Execute all operations
	M.execute_operations_sequence(operations, function(results)
		local has_error = false
		local error_messages = {}

		for i, result in ipairs(results) do
			if result.error then
				has_error = true
				table.insert(error_messages, "Operation " .. i .. ": " .. result.error)
			end
		end

		if has_error then
			vim.schedule(function()
				local error_msg = "Sync errors occurred:\n" .. table.concat(error_messages, "\n")
				callback({ error = error_msg })
			end)
		else
			vim.schedule(function()
				callback({
					data = {
						success = true,
						created_items = created_items, -- Return created items for extmark updates
					},
				})
			end)
		end
	end)
end

-- Helper function to calculate effective depth from indent string
function M.calculate_effective_depth(indent_str)
	local effective_indent = 0

	for i = 1, #indent_str do
		local char = indent_str:sub(i, i)
		if char == "\t" then
			effective_indent = effective_indent + 2
		elseif char == " " then
			effective_indent = effective_indent + 1
		end
	end

	return math.floor(effective_indent / 2)
end

function M.execute_operations_sequence(operations, callback)
	local results = {}
	local current = 1

	local function execute_next()
		if current > #operations then
			callback(results)
			return
		end

		operations[current](function(result)
			table.insert(results, result)
			current = current + 1
			vim.schedule(execute_next)
		end)
	end

	if #operations == 0 then
		vim.schedule(function()
			callback(results)
		end)
	else
		execute_next()
	end
end

return M
