-- Sync engine for bidirectional synchronization
local M = {}

local api = require("todoist.api")
local parser = require("todoist.parser")
local config = require("todoist.config")

function M.sync_buffer_changes(project_id, lines, extmarks, callback)
	local changes = parser.parse_markdown_to_changes(lines, extmarks)

	if config.is_debug() then
		print("DEBUG: Sync changes:", vim.inspect(changes))
	end

	-- Execute changes in order: deletes, updates, creates
	M.execute_sync_operations(project_id, changes, lines, callback)
end

function M.execute_sync_operations(project_id, changes, lines, callback)
	local operations = {}
	local created_items = {} -- Track items created during sync

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
					print("DEBUG: Updating task:", task.id, "content:", task.content, "completed:", task.is_completed)
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
					local completion_needs_toggle = current_task.is_completed ~= task.is_completed

					if config.is_debug() then
						print(
							"DEBUG: Current task state - content:",
							current_task.content,
							"completed:",
							current_task.is_completed
						)
						print("DEBUG: Desired task state - content:", task.content, "completed:", task.is_completed)
						print(
							"DEBUG: Needs content update:",
							content_needs_update,
							"needs completion toggle:",
							completion_needs_toggle
						)
					end

					-- Update content if needed
					if content_needs_update then
						api.update_task(task.id, task.content, function(update_result)
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
						-- Only toggle completion if content doesn't need updating
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

	-- Create operations with tracking
	for _, section in ipairs(changes.created_sections) do
		if config.is_valid(section) and config.is_valid(section.name) then
			table.insert(operations, function(cb)
				if config.is_debug() then
					print("DEBUG: Creating section:", section.name)
				end
				api.create_section(project_id, section.name, function(result)
					if not result.error and result.data and result.data.id then
						-- Track the created section
						created_items[section.line] = {
							type = "section",
							id = tostring(result.data.id),
							name = section.name,
						}
						if config.is_debug() then
							print("DEBUG: Section created with ID:", result.data.id)
						end
					end
					cb(result)
				end)
			end)
		end
	end

	for _, task in ipairs(changes.created_tasks) do
		if config.is_valid(task) and config.is_valid(task.content) then
			table.insert(operations, function(cb)
				if config.is_debug() then
					print("DEBUG: Creating task:", task.content)
				end
				api.create_task(project_id, task.content, nil, nil, function(result)
					if not result.error and result.data and result.data.id then
						-- Track the created task
						created_items[task.line] = {
							type = "task",
							id = tostring(result.data.id),
							content = task.content,
							is_completed = task.is_completed or false,
						}
						if config.is_debug() then
							print("DEBUG: Task created with ID:", result.data.id)
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

