-- Buffer management and UI integration
local M = {}

local api = require("todoist.api")
local parser = require("todoist.parser")
local sync = require("todoist.sync")
local config = require("todoist.config")

M.namespace_id = vim.api.nvim_create_namespace("todoist")
M.buffers = {} -- Track todoist buffers

function M.open_project(project_id)
	if not config.is_valid(project_id) then
		vim.notify("Invalid project ID", vim.log.levels.ERROR)
		return
	end

	-- Create or focus existing buffer for this project
	local buf_name = "todoist://project/" .. project_id
	local existing_buf = vim.fn.bufnr(buf_name)

	if existing_buf ~= -1 then
		-- Buffer exists, switch to it
		local win = vim.fn.bufwinid(existing_buf)
		if win ~= -1 then
			vim.api.nvim_set_current_win(win)
		else
			vim.cmd("buffer " .. existing_buf)
		end
		return existing_buf
	end

	-- Create new buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, buf_name)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)

	-- Store buffer info
	M.buffers[buf] = {
		project_id = project_id,
		last_sync = 0,
	}

	-- Set up buffer
	vim.api.nvim_set_current_buf(buf)
	M.setup_buffer_autocmds(buf)
	M.setup_buffer_keymaps(buf)

	-- Load project data
	M.load_project_data(buf, project_id)

	return buf
end

function M.load_project_data(buf, project_id)
	if config.is_debug() then
		print("DEBUG: Loading project data for buffer", buf, "project", project_id)
	end

	api.get_project_data(project_id, function(result)
		vim.schedule(function()
			if result.error then
				vim.notify("Failed to load project: " .. result.error, vim.log.levels.ERROR)
				return
			end

			if config.is_debug() then
				print("DEBUG: Received project data, rendering...")
			end

			M.render_project_data(buf, result.data)
		end)
	end)
end

function M.render_project_data(buf, project_data)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	-- Convert project data to markdown
	local markdown_data = parser.project_to_markdown(project_data)

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, markdown_data.lines)

	-- Set extmarks
	parser.set_extmarks(buf, M.namespace_id, markdown_data.extmarks)

	-- Mark buffer as not modified
	vim.api.nvim_buf_set_option(buf, "modified", false)

	if config.is_debug() then
		print("DEBUG: Rendered", #markdown_data.lines, "lines and", #markdown_data.extmarks, "extmarks")
	end
end

function M.sync_buffer(buf)
	local buffer_info = M.buffers[buf]
	if not buffer_info then
		vim.notify("Buffer is not a Todoist project buffer", vim.log.levels.ERROR)
		return
	end

	local project_id = buffer_info.project_id

	if config.is_debug() then
		print("DEBUG: Starting bidirectional sync for buffer", buf, "project", project_id)
	end

	-- Get current buffer content
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local extmarks = parser.get_extmarks_with_data(buf, M.namespace_id)

	if config.is_debug() then
		print("DEBUG: Buffer has", #lines, "lines and", #extmarks, "extmarks")
	end

	-- Show sync status
	vim.notify("Syncing with Todoist...", vim.log.levels.INFO)

	-- Perform bidirectional sync
	sync.sync_buffer_changes(project_id, lines, extmarks, function(result)
		vim.schedule(function()
			if result.error then
				vim.notify("Sync failed: " .. result.error, vim.log.levels.ERROR)
				return
			end

			if config.is_debug() then
				print("DEBUG: Sync completed successfully")
			end

			-- Update buffer with latest data
			if result.data.project_data then
				M.render_project_data(buf, result.data.project_data)

				-- Update extmarks for newly created items
				if result.data.created_items then
					parser.update_extmarks_with_created_items(buf, M.namespace_id, result.data.created_items)
				end
			end

			-- Update last sync time
			M.buffers[buf].last_sync = vim.fn.localtime()

			vim.notify("Sync completed successfully!", vim.log.levels.INFO)
		end)
	end)
end

function M.setup_buffer_autocmds(buf)
	local group = vim.api.nvim_create_augroup("TodoistBuffer" .. buf, { clear = true })

	-- Auto-sync on save
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = group,
		buffer = buf,
		callback = function()
			M.sync_buffer(buf)
		end,
	})

	-- Clean up when buffer is deleted
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		buffer = buf,
		callback = function()
			M.buffers[buf] = nil
		end,
	})
end

function M.setup_buffer_keymaps(buf)
	local opts = { buffer = buf, silent = true }

	-- Toggle task completion
	vim.keymap.set("n", "<CR>", function()
		M.toggle_task_under_cursor(buf)
	end, opts)

	-- Manual sync
	vim.keymap.set("n", "<leader>ts", function()
		M.sync_buffer(buf)
	end, opts)

	-- Refresh from server
	vim.keymap.set("n", "<leader>tr", function()
		M.refresh_buffer(buf)
	end, opts)
end

function M.refresh_buffer(buf)
	local buffer_info = M.buffers[buf]
	if not buffer_info then
		return
	end

	vim.notify("Refreshing from Todoist...", vim.log.levels.INFO)
	M.load_project_data(buf, buffer_info.project_id)
end

function M.toggle_task_under_cursor(buf)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_num = cursor[1] - 1 -- Convert to 0-indexed

	-- Get extmarks for this line
	local extmarks = parser.get_extmarks_with_data(buf, M.namespace_id)
	local task_data = nil

	for _, mark in ipairs(extmarks) do
		if mark[2] == line_num and mark[4] and mark[4].type == "task" then
			task_data = mark[4]
			break
		end
	end

	if not task_data then
		return -- No task on this line
	end

	-- Toggle completion status
	local new_completion = not task_data.completed

	-- Update the line locally
	local line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]
	local updated_line
	if new_completion then
		updated_line = line:gsub("%- %[ %]", "- [x]")
	else
		updated_line = line:gsub("%- %[x%]", "- [ ]")
	end

	if updated_line ~= line then
		vim.api.nvim_buf_set_lines(buf, line_num, line_num + 1, false, { updated_line })

		-- Mark buffer as modified for auto-sync
		vim.api.nvim_buf_set_option(buf, "modified", true)

		if config.is_debug() then
			print("DEBUG: Toggled task completion for task ID:", task_data.id)
		end
	end
end

function M.get_project_buffers()
	local project_buffers = {}
	for buf, info in pairs(M.buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			project_buffers[buf] = info
		else
			M.buffers[buf] = nil -- Clean up invalid buffers
		end
	end
	return project_buffers
end

return M
