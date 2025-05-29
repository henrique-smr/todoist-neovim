-- Todoist.nvim - A Neovim plugin for Todoist integration with markdown
-- Author: AI Assistant
-- License: MIT

local M = {}

-- Configuration
M.config = {
	api_token = nil,
	auto_sync = true,
	sync_interval = 30000, -- 30 seconds
	debug = false,
}

-- Internal state
local projects = {}
local current_project = nil
local sync_timer = nil
local ns_id = vim.api.nvim_create_namespace("todoist")

-- Todoist API client
local api = require("todoist.api")
local parser = require("todoist.parser")
local sync = require("todoist.sync")
local ui = require("todoist.ui")

-- Setup function
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	if not M.config.api_token then
		vim.notify("Todoist API token not provided. Please set it in your config.", vim.log.levels.ERROR)
		return
	end

	api.set_token(M.config.api_token)

	-- Create user commands
	vim.api.nvim_create_user_command("TodoistProjects", M.list_projects, {})
	vim.api.nvim_create_user_command("TodoistCreateProject", function(opts)
		M.create_project(opts.args)
	end, { nargs = 1 })
	vim.api.nvim_create_user_command("TodoistOpen", function(opts)
		M.open_project(opts.args)
	end, { nargs = 1, complete = M.complete_projects })
	vim.api.nvim_create_user_command("TodoistSync", M.sync_current_buffer, {})
	vim.api.nvim_create_user_command("TodoistToggle", M.toggle_task, {})

	-- Create autocommands
	local augroup = vim.api.nvim_create_augroup("TodoistNvim", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		pattern = "*.todoist.md",
		callback = function()
			if M.config.auto_sync then
				M.sync_current_buffer()
			end
		end,
	})

	-- Set up auto-sync timer
	if M.config.auto_sync then
		M.start_auto_sync()
	end

	-- Key mappings for todoist buffers
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = "markdown",
		callback = function()
			local bufname = vim.api.nvim_buf_get_name(0)
			if bufname:match("%.todoist%.md$") then
				vim.keymap.set({ "n", "i" }, "<C-t>", M.toggle_task, { buffer = true })
				vim.keymap.set("n", "<leader>ts", M.sync_current_buffer, { buffer = true })
			end
		end,
	})
end

-- List all projects
function M.list_projects()
	api.get_projects(function(result)
		if result.error then
			vim.notify("Error fetching projects: " .. result.error, vim.log.levels.ERROR)
			return
		end

		projects = result.data
		ui.show_project_list(projects, M.open_project)
	end)
end

-- Create a new project
function M.create_project(name)
	if not name or name == "" then
		vim.ui.input({ prompt = "Project name: " }, function(input)
			if input and input ~= "" then
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

-- Open a project as markdown
function M.open_project(project_name)
	local project = nil
	for _, p in ipairs(projects) do
		if p.name == project_name then
			project = p
			break
		end
	end

	if not project then
		vim.notify("Project not found: " .. project_name, vim.log.levels.ERROR)
		return
	end

	current_project = project

	-- Get project data with tasks and sections
	api.get_project_data(project.id, function(result)
		if result.error then
			vim.notify("Error fetching project data: " .. result.error, vim.log.levels.ERROR)
			return
		end

		-- Add project info to the data
		result.data.project = project

		local filename = project.name:gsub("[^%w%s%-_]", "") .. ".todoist.md"
		local filepath = vim.fn.expand("~/todoist/" .. filename)

		-- Ensure directory exists
		vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")

		-- Create buffer
		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, filepath)

		-- Generate markdown content
		local content = parser.project_to_markdown(result.data)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, content.lines)

		-- Set extmarks for tracking
		parser.set_extmarks(buf, ns_id, content.extmarks)

		-- Open buffer in current window
		vim.api.nvim_set_current_buf(buf)
		vim.bo.filetype = "markdown"
		vim.bo.modified = false

		vim.notify("Opened project: " .. project.name, vim.log.levels.INFO)
	end)
end

-- Sync current buffer with Todoist
function M.sync_current_buffer()
	local buf = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(buf)

	if not bufname:match("%.todoist%.md$") then
		vim.notify("Not a Todoist buffer", vim.log.levels.WARN)
		return
	end

	if not current_project then
		vim.notify("No current project", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })

	sync.sync_buffer_changes(current_project.id, lines, extmarks, function(result)
		if result.error then
			vim.notify("Sync error: " .. result.error, vim.log.levels.ERROR)
			return
		end

		vim.notify("Synced successfully!", vim.log.levels.INFO)
		vim.bo.modified = false

		-- Update extmarks with new data
		if result.data and result.data.extmarks then
			vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
			parser.set_extmarks(buf, ns_id, result.data.extmarks)
		end
	end)
end

-- Toggle task completion
function M.toggle_task()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_num = cursor[1] - 1

	-- Find extmark for current line or nearby lines
	local extmarks = vim.api.nvim_buf_get_extmarks(
		buf,
		ns_id,
		{ line_num - 2, 0 },
		{ line_num + 2, -1 },
		{ details = true }
	)

	local task_extmark = nil
	for _, mark in ipairs(extmarks) do
		local data = mark[4]
		if data and data.todoist_type == "task" then
			task_extmark = mark
			break
		end
	end

	if not task_extmark then
		vim.notify("No task found on current line", vim.log.levels.WARN)
		return
	end

	local task_id = task_extmark[4].todoist_id
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

	-- Sync with Todoist API
	local is_completed = new_line:match("%- %[x%]") ~= nil
	api.toggle_task(task_id, is_completed, function(result)
		if result.error then
			vim.notify("Error toggling task: " .. result.error, vim.log.levels.ERROR)
			-- Revert the change
			vim.api.nvim_buf_set_lines(buf, line_num, line_num + 1, false, { current_line })
		else
			vim.notify("Task " .. (is_completed and "completed" or "reopened"), vim.log.levels.INFO)
		end
	end)
end

-- Auto-sync functionality
function M.start_auto_sync()
	if sync_timer then
		vim.loop.timer_stop(sync_timer)
	end

	sync_timer = vim.loop.new_timer()
	sync_timer:start(
		M.config.sync_interval,
		M.config.sync_interval,
		vim.schedule_wrap(function()
			local buf = vim.api.nvim_get_current_buf()
			local bufname = vim.api.nvim_buf_get_name(buf)

			if bufname:match("%.todoist%.md$") and not vim.bo.modified then
				M.sync_current_buffer()
			end
		end)
	)
end

function M.stop_auto_sync()
	if sync_timer then
		vim.loop.timer_stop(sync_timer)
		sync_timer = nil
	end
end

-- Completion function for project names
function M.complete_projects(arg_lead, cmd_line, cursor_pos)
	local matches = {}
	for _, project in ipairs(projects) do
		if project.name:lower():find(arg_lead:lower(), 1, true) then
			table.insert(matches, project.name)
		end
	end
	return matches
end

return M
