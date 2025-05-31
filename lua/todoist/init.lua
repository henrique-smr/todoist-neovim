-- Todoist.nvim - A Neovim plugin for Todoist integration with markdown
-- Author: AI Assistant
-- License: MIT

local M = {}

-- Load modules
local config = require("todoist.config")
local api = require("todoist.api")
local parser = require("todoist.parser")
local sync = require("todoist.sync")
local ui = require("todoist.ui")
local buffer = require("todoist.buffer")

-- Internal state
local projects = {}
local current_project = nil
local sync_timer = nil
local ns_id = buffer.namespace_id or vim.api.nvim_create_namespace("todoist")

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Setup configuration and validate
	config.setup(opts)

	if not config.is_valid(config.get_token()) then
		vim.notify("Todoist API token not provided. Please set it in your config.", vim.log.levels.ERROR)
		return false
	end

	api.set_token(config.get_token())

	-- Create user commands
	M.setup_commands()

	-- Create autocommands
	local augroup = vim.api.nvim_create_augroup("TodoistNvim", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		pattern = "*.todoist.md",
		callback = function()
			if config.get_auto_sync() then
				M.sync_current_buffer()
			end
		end,
	})

	-- Set up auto-sync timer
	if config.get_auto_sync() then
		M.start_auto_sync()
	end

	-- Key mappings for todoist buffers
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = "markdown",
		callback = function()
			local bufname = vim.api.nvim_buf_get_name(0)
			if bufname:match("%.todoist%.md$") or bufname:match("^todoist://") then
				vim.keymap.set({ "n", "i" }, "<C-t>", M.toggle_task, { buffer = true })
				vim.keymap.set("n", "<leader>ts", M.sync_current_buffer, { buffer = true })
			end
		end,
	})

	if config.is_debug() then
		print("DEBUG: Todoist.nvim setup completed")
	end

	return true
end

-- Setup commands
function M.setup_commands()
	vim.api.nvim_create_user_command("TodoistProjects", M.list_projects, {
		desc = "List and select Todoist projects",
	})

	vim.api.nvim_create_user_command("TodoistCreateProject", function(opts)
		M.create_project(opts.args)
	end, {
		nargs = 1,
		desc = "Create a new Todoist project",
	})

	vim.api.nvim_create_user_command("TodoistOpen", function(opts)
		if opts.args and opts.args ~= "" then
			-- Try to open by name first, then by ID
			if tonumber(opts.args) then
				M.open_project_by_id(opts.args)
			else
				M.open_project(opts.args)
			end
		else
			vim.notify("Usage: :TodoistOpen <project_name_or_id>", vim.log.levels.ERROR)
		end
	end, {
		nargs = 1,
		complete = M.complete_projects,
		desc = "Open specific Todoist project by name or ID",
	})

	vim.api.nvim_create_user_command("TodoistSync", M.sync_current_buffer, {
		desc = "Sync current Todoist buffer",
	})

	vim.api.nvim_create_user_command("TodoistRefresh", M.refresh_current_buffer, {
		desc = "Refresh current Todoist buffer from server",
	})

	vim.api.nvim_create_user_command("TodoistToggle", M.toggle_task, {
		desc = "Toggle task completion under cursor",
	})

	vim.api.nvim_create_user_command("TodoistDebug", M.debug_config, {
		desc = "Debug Todoist configuration and API connection",
	})
end

-- List all projects - integrates with buffer.lua
function M.list_projects()
	api.get_projects(function(result)
		if result.error then
			vim.notify("Error fetching projects: " .. result.error, vim.log.levels.ERROR)
			return
		end

		projects = result.data or {}
		if config.is_debug() then
			print("DEBUG: Fetched projects:", vim.inspect(projects))
		end

		-- Use buffer.lua's project selection if available, otherwise fallback to ui.lua
		if buffer.show_project_list then
			buffer.show_project_list(projects)
		else
			ui.show_project_list(projects, M.open_project_by_id)
		end
	end)
end

-- Create a new project
function M.create_project(name)
	if not config.is_valid(name) or name == "" then
		vim.ui.input({ prompt = "Project name: " }, function(input)
			if config.is_valid(input) and input ~= "" then
				M.create_project(input)
			end
		end)
		return
	end

	api.create_project(name, function(result)
		if result.error then
			vim.notify("Error creating project: " .. result.error, vim.log.levels.ERROR)
			return
		end

		vim.notify("Project '" .. name .. "' created successfully!", vim.log.levels.INFO)
		M.list_projects() -- Refresh project list
	end)
end

-- Open a project by name (backward compatibility)
function M.open_project(project_name)
	local project = nil
	for _, p in ipairs(projects) do
		if config.is_valid(p.name) and p.name == project_name then
			project = p
			break
		end
	end

	if not project then
		-- Try to fetch projects if not loaded
		api.get_projects(function(result)
			if result.error then
				vim.notify("Error fetching projects: " .. result.error, vim.log.levels.ERROR)
				return
			end

			projects = result.data or {}
			for _, p in ipairs(projects) do
				if config.is_valid(p.name) and p.name == project_name then
					project = p
					break
				end
			end

			if project then
				M.open_project_by_id(project.id)
			else
				vim.notify("Project not found: " .. project_name, vim.log.levels.ERROR)
			end
		end)
		return
	end

	M.open_project_by_id(project.id)
end

-- Open project by ID - delegates to buffer.lua
function M.open_project_by_id(project_id)
	if not config.is_valid(project_id) then
		vim.notify("Invalid project ID", vim.log.levels.ERROR)
		return
	end

	-- Store current project for backward compatibility
	for _, p in ipairs(projects) do
		if p.id == project_id or tostring(p.id) == tostring(project_id) then
			current_project = p
			break
		end
	end

	if config.is_debug() then
		print("DEBUG: Opening project ID:", project_id)
	end

	-- Use buffer.lua to handle the actual opening
	buffer.open_project(project_id)
end

-- Sync current buffer - enhanced to work with both old and new buffers
function M.sync_current_buffer()
	local buf = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(buf)

	-- Check if it's a buffer.lua managed buffer
	if buffer.buffers[buf] then
		buffer.sync_buffer(buf)
		return
	end

	-- Fallback for old-style buffers
	if not bufname:match("%.todoist%.md$") then
		vim.notify("Not a Todoist buffer", vim.log.levels.WARN)
		return
	end

	if not current_project then
		vim.notify("No current project", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local extmarks = parser.get_extmarks_with_data(buf, ns_id)

	if config.is_debug() then
		print("DEBUG: Syncing legacy buffer with", #lines, "lines and", #extmarks, "extmarks")
	end

	sync.sync_buffer_changes(current_project.id, lines, extmarks, function(result)
		if result.error then
			vim.notify("Sync error: " .. result.error, vim.log.levels.ERROR)
			return
		end

		vim.notify("Synced successfully!", vim.log.levels.INFO)
		vim.bo.modified = false

		-- Update extmarks with newly created items
		if result.data and result.data.created_items then
			vim.schedule(function()
				parser.update_extmarks_with_created_items(buf, ns_id, result.data.created_items)
			end)
		end
	end)
end

-- Refresh current buffer
function M.refresh_current_buffer()
	local buf = vim.api.nvim_get_current_buf()

	-- Check if it's a buffer.lua managed buffer
	if buffer.buffers[buf] then
		buffer.refresh_buffer(buf)
		return
	end

	-- Fallback for legacy buffers
	if not current_project then
		vim.notify("No current project to refresh", vim.log.levels.WARN)
		return
	end

	M.open_project_by_id(current_project.id)
end

-- Toggle task completion - enhanced to work with both buffer types
function M.toggle_task()
	local buf = vim.api.nvim_get_current_buf()

	-- Check if it's a buffer.lua managed buffer
	if buffer.buffers[buf] and buffer.toggle_task_under_cursor then
		buffer.toggle_task_under_cursor(buf)
		return
	end

	-- Fallback for legacy buffers or direct toggle
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_num = cursor[1] - 1

	local extmarks = parser.get_extmarks_with_data(buf, ns_id)

	local task_extmark = nil
	for _, mark in ipairs(extmarks) do
		local mark_line = mark[2]
		local data = mark[4]
		if config.is_valid(data) and data.type == "task" and math.abs(mark_line - line_num) <= 2 then
			task_extmark = mark
			break
		end
	end

	if not task_extmark then
		vim.notify("No task found on current line", vim.log.levels.WARN)
		return
	end

	local task_id = task_extmark[4].id
	local current_line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]

	-- Toggle checkbox in markdown
	local new_line
	if current_line:match("%- %[ %]") then
		new_line = current_line:gsub("%- %[ %]", "- [x]")
	elseif current_line:match("%- %[x%]") then
		new_line = current_line:gsub("%- %[x%]", "- [ ]")
	else
		vim.notify("Current line is not a task", vim.log.levels.WARN)
		return
	end

	-- Update buffer
	vim.api.nvim_buf_set_lines(buf, line_num, line_num + 1, false, { new_line })

	-- Get current task state
	local current_completed = task_extmark[4].completed
	local new_completed = new_line:match("%- %[x%]") ~= nil

	if config.is_debug() then
		print("DEBUG: Toggle task - current completed:", current_completed, "new completed:", new_completed)
	end

	-- Only sync if the state actually changed
	if current_completed ~= new_completed then
		api.toggle_task(task_id, new_completed, function(result)
			if result.error then
				vim.notify("Error toggling task: " .. result.error, vim.log.levels.ERROR)
				-- Revert the change
				vim.api.nvim_buf_set_lines(buf, line_num, line_num + 1, false, { current_line })
			else
				vim.notify("Task " .. (new_completed and "completed" or "reopened"), vim.log.levels.INFO)

				-- Update stored extmark data
				local extmark_data_store = parser.get_extmark_data_store()
				if extmark_data_store[buf] and extmark_data_store[buf][task_extmark[1]] then
					extmark_data_store[buf][task_extmark[1]].completed = new_completed
				end
			end
		end)
	end
end

-- Auto-sync functionality
function M.start_auto_sync()
	if sync_timer then
		vim.loop.timer_stop(sync_timer)
	end

	sync_timer = vim.loop.new_timer()
	sync_timer:start(
		config.get_sync_interval(),
		config.get_sync_interval(),
		vim.schedule_wrap(function()
			local buf = vim.api.nvim_get_current_buf()
			local bufname = vim.api.nvim_buf_get_name(buf)

			-- Check both buffer types
			local is_todoist_buffer = (
				bufname:match("%.todoist%.md$")
				or bufname:match("^todoist://")
				or buffer.buffers[buf]
			)

			if is_todoist_buffer and not vim.bo.modified then
				M.sync_current_buffer()
			end
		end)
	)

	if config.is_debug() then
		print("DEBUG: Auto-sync timer started with interval:", config.get_sync_interval())
	end
end

function M.stop_auto_sync()
	if sync_timer then
		vim.loop.timer_stop(sync_timer)
		sync_timer = nil
		if config.is_debug() then
			print("DEBUG: Auto-sync timer stopped")
		end
	end
end

-- Completion function for project names
function M.complete_projects(arg_lead, cmd_line, cursor_pos)
	local matches = {}
	for _, project in ipairs(projects) do
		if config.is_valid(project.name) and project.name:lower():find(arg_lead:lower(), 1, true) then
			table.insert(matches, project.name)
		end
	end
	return matches
end

-- Debug function
function M.debug_config()
	print("=== Todoist Configuration Debug ===")
	print("API Token:", config.get_token() and "SET" or "NOT SET")
	print("Debug mode:", config.is_debug())
	print("Auto sync:", config.get_auto_sync())
	print("Sync interval:", config.get_sync_interval())
	print("Config:", vim.inspect(config.get_config()))

	-- Buffer info
	local buf = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(buf)
	print("Current buffer:", bufname)
	print("Is Todoist buffer (buffer.lua):", buffer.buffers[buf] ~= nil)
	print("Is legacy Todoist buffer:", bufname:match("%.todoist%.md$") ~= nil)
	print("Buffer count (buffer.lua):", vim.tbl_count(buffer.buffers))

	-- Test API connection
	if config.get_token() then
		api.get_projects(function(result)
			if result.error then
				print("API Test FAILED:", result.error)
			else
				print("API Test SUCCESS: Found", #result.data, "projects")
				projects = result.data -- Update local cache
			end
		end)
	else
		print("Cannot test API - no token configured")
	end
end

-- Get namespace ID (for external access)
function M.get_namespace_id()
	return ns_id
end

-- Get current project (for external access)
function M.get_current_project()
	return current_project
end

-- Get projects list (for external access)
function M.get_projects()
	return projects
end

-- Set current project (for external modules)
function M.set_current_project(project)
	current_project = project
end

return M
