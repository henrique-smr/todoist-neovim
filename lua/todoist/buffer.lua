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

	if config.is_debug() then
		print("DEBUG: Opening project with buffer.lua:", project_id)
	end

	-- Create or focus existing buffer for this project
	local buf_name = "todoist://project/" .. project_id
	local existing_buf = vim.fn.bufnr(buf_name)

	if existing_buf ~= -1 then
		-- Buffer exists, check if it's in a tab
		local existing_tab = M.find_buffer_tab(existing_buf)
		if existing_tab then
			vim.api.nvim_set_current_tabpage(existing_tab)
			local win = vim.fn.bufwinid(existing_buf)
			if win ~= -1 then
				vim.api.nvim_set_current_win(win)
			end
		else
			-- Open in new tab
			vim.cmd("tabnew")
			vim.api.nvim_set_current_buf(existing_buf)
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

	-- Open in new tab
	vim.cmd("tabnew")
	vim.api.nvim_set_current_buf(buf)

	-- Set up buffer
	M.setup_buffer_autocmds(buf)
	M.setup_buffer_keymaps(buf)

	-- Load project data
	M.load_project_data(buf, project_id)

	if config.is_debug() then
		print("DEBUG: Created new Todoist buffer:", buf, "in new tab")
	end

	return buf
end

function M.find_buffer_tab(buf)
	for i = 1, vim.fn.tabpagenr("$") do
		local tab_buffers = vim.fn.tabpagebuflist(i)
		for _, tab_buf in ipairs(tab_buffers) do
			if tab_buf == buf then
				return i
			end
		end
	end
	return nil
end

function M.close_buffer_and_tab(buf)
	local tab = M.find_buffer_tab(buf)
	if tab then
		-- Store current tab to switch back after closing
		local current_tab = vim.fn.tabpagenr()

		if tab == current_tab then
			-- We're in the tab we want to close
			if vim.fn.tabpagenr("$") > 1 then
				vim.cmd("tabclose")
			else
				-- Last tab, just close the buffer
				vim.cmd("bdelete " .. buf)
			end
		else
			-- Switch to tab and close it
			vim.api.nvim_set_current_tabpage(tab)
			if vim.fn.tabpagenr("$") > 1 then
				vim.cmd("tabclose")
			else
				vim.cmd("bdelete " .. buf)
			end
			-- Switch back to original tab if it still exists
			if current_tab <= vim.fn.tabpagenr("$") then
				vim.api.nvim_set_current_tabpage(current_tab)
			end
		end
	else
		-- Buffer not in a tab, just delete it
		vim.cmd("bdelete " .. buf)
	end

	-- Clean up buffer tracking
	M.buffers[buf] = nil

	if config.is_debug() then
		print("DEBUG: Closed Todoist buffer and tab:", buf)
	end
end

function M.find_task_positions(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local task_positions = {}

	for i, line in ipairs(lines) do
		-- Match task lines: "  - [ ] Task" or "  - [x] Task"
		local indent, checkbox = line:match("^(%s*)%- %[([%sx])%]")
		if checkbox then
			-- Calculate position between the brackets
			local bracket_pos = #indent + 3 -- Position after "- ["
			table.insert(task_positions, {
				line = i - 1, -- Convert to 0-indexed
				col = bracket_pos,
				completed = checkbox == "x",
			})
		end
	end

	return task_positions
end

function M.navigate_to_task(buf, direction)
	local task_positions = M.find_task_positions(buf)
	if #task_positions == 0 then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1] - 1 -- Convert to 0-indexed
	local current_col = cursor[2]

	local current_idx = nil

	-- Find current task position
	for i, pos in ipairs(task_positions) do
		if pos.line == current_line then
			current_idx = i
			break
		end
	end

	local target_idx
	if current_idx then
		-- We're on a task line, move to next/previous
		if direction == "next" then
			target_idx = current_idx < #task_positions and current_idx + 1 or 1
		else
			target_idx = current_idx > 1 and current_idx - 1 or #task_positions
		end
	else
		-- Not on a task line, find nearest task
		if direction == "next" then
			-- Find first task after current line
			for i, pos in ipairs(task_positions) do
				if pos.line > current_line then
					target_idx = i
					break
				end
			end
			-- If no task after, go to first task
			target_idx = target_idx or 1
		else
			-- Find last task before current line
			for i = #task_positions, 1, -1 do
				local pos = task_positions[i]
				if pos.line < current_line then
					target_idx = i
					break
				end
			end
			-- If no task before, go to last task
			target_idx = target_idx or #task_positions
		end
	end

	if target_idx then
		local target_pos = task_positions[target_idx]
		-- Position cursor between the brackets
		vim.api.nvim_win_set_cursor(0, { target_pos.line + 1, target_pos.col })

		if config.is_debug() then
			print("DEBUG: Navigated to task at line", target_pos.line + 1, "col", target_pos.col)
		end
	end
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

	-- Store cursor position
	local cursor_pos = vim.api.nvim_win_get_cursor(0)

	-- Convert project data to markdown
	local markdown_data = parser.project_to_markdown(project_data)

	-- Clear existing extmarks
	vim.api.nvim_buf_clear_namespace(buf, M.namespace_id, 0, -1)

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, markdown_data.lines)

	-- Set extmarks
	parser.set_extmarks(buf, M.namespace_id, markdown_data.extmarks)

	-- Restore cursor position (with bounds checking)
	local line_count = vim.api.nvim_buf_line_count(buf)
	local target_line = math.min(cursor_pos[1], line_count)
	local line_content = vim.api.nvim_buf_get_lines(buf, target_line - 1, target_line, false)[1] or ""
	local target_col = math.min(cursor_pos[2], #line_content)

	vim.api.nvim_win_set_cursor(0, { target_line, target_col })

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
				print("DEBUG: Has project_data:", result.data.project_data ~= nil)
				print("DEBUG: Has created_items:", result.data.created_items ~= nil)
			end

			-- Always update buffer with latest data
			if result.data.project_data then
				if config.is_debug() then
					print("DEBUG: Updating buffer with fresh project data")
				end
				M.render_project_data(buf, result.data.project_data)

				-- Update extmarks for newly created items
				if result.data.created_items and vim.tbl_count(result.data.created_items) > 0 then
					if config.is_debug() then
						print("DEBUG: Updating extmarks for", vim.tbl_count(result.data.created_items), "created items")
					end
					parser.update_extmarks_with_created_items(buf, M.namespace_id, result.data.created_items)
				end
			else
				-- Fallback: reload project data if no project_data in result
				if config.is_debug() then
					print("DEBUG: No project_data in sync result, reloading...")
				end
				M.load_project_data(buf, project_id)
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

	-- Task navigation
	vim.keymap.set("n", "<Tab>", function()
		M.navigate_to_task(buf, "next")
	end, opts)

	vim.keymap.set("n", "<S-Tab>", function()
		M.navigate_to_task(buf, "prev")
	end, opts)

	-- Close buffer and tab with double ESC
	local esc_timer = nil
	vim.keymap.set("n", "<Esc>", function()
		if esc_timer then
			-- Second ESC press within timeout
			vim.fn.timer_stop(esc_timer)
			esc_timer = nil
			M.close_buffer_and_tab(buf)
		else
			-- First ESC press, start timer
			esc_timer = vim.fn.timer_start(500, function() -- 500ms timeout
				esc_timer = nil
			end)
		end
	end, opts)

	if config.is_debug() then
		print("DEBUG: Set up Todoist buffer keymaps for buffer", buf)
	end
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
