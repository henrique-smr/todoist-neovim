-- Sync engine for bidirectional synchronization
local M = {}

local api = require("todoist.api")
local parser = require("todoist.parser")

function M.sync_buffer_changes(project_id, lines, extmarks, callback)
	local changes = parser.parse_markdown_to_changes(lines, extmarks)

	-- Execute changes in order: deletes, updates, creates
	M.execute_sync_operations(project_id, changes, callback)
end

function M.execute_sync_operations(project_id, changes, callback)
	local operations = {}

	-- Delete operations
	for _, task_id in ipairs(changes.deleted_tasks) do
		table.insert(operations, function(cb)
			api.delete_task(task_id, cb)
		end)
	end

	for _, section_id in ipairs(changes.deleted_sections) do
		table.insert(operations, function(cb)
			api.delete_section(section_id, cb)
		end)
	end

	-- Update operations
	for _, task in ipairs(changes.updated_tasks) do
		table.insert(operations, function(cb)
			api.update_task(task.id, task.content, cb)
		end)
	end

	for _, section in ipairs(changes.updated_sections) do
		table.insert(operations, function(cb)
			api.update_section(section.id, section.name, cb)
		end)
	end

	-- Create operations
	for _, section in ipairs(changes.created_sections) do
		table.insert(operations, function(cb)
			api.create_section(project_id, section.name, cb)
		end)
	end

	for _, task in ipairs(changes.created_tasks) do
		table.insert(operations, function(cb)
			api.create_task(project_id, task.content, nil, nil, cb)
		end)
	end

	-- Execute all operations
	M.execute_operations_sequence(operations, function(results)
		local has_error = false
		for _, result in ipairs(results) do
			if result.error then
				has_error = true
				break
			end
		end

		if has_error then
			vim.schedule(function()
				callback({ error = "Some sync operations failed" })
			end)
		else
			vim.schedule(function()
				callback({ data = { success = true } })
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
