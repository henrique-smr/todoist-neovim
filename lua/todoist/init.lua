-- Main plugin entry point
local M = {}

local config = require("todoist.config")

function M.setup(opts)
	opts = opts or {}

	-- Setup configuration and validate
	config.setup(opts)

	-- Only load other modules after successful config
	local api = require("todoist.api")

	if config.is_debug() then
		print("DEBUG: Todoist.nvim plugin setup completed successfully")
	end

	api.set_token(config.get_token())

	-- Setup commands after successful configuration
	M.setup_commands()

	return true
end

function M.select_project()
	if config.is_debug() then
		print("DEBUG: Starting project selection")
	end

	local api = require("todoist.api")

	api.get_projects(function(result)
		if result.error then
			vim.notify("Failed to fetch projects: " .. result.error, vim.log.levels.ERROR)
			return
		end

		if config.is_debug() then
			print("DEBUG: Fetched projects:", vim.inspect(result.data))
		end

		M.show_project_list(result.data)
	end)
end

function M.show_project_list(projects)
	if config.is_debug() then
		print("DEBUG: Showing project list with", #projects, "projects")
	end

	-- Create project selection items
	local items = {}
	for _, project in ipairs(projects) do
		if config.is_valid(project) and config.is_valid(project.name) then
			table.insert(items, {
				text = project.name,
				data = project,
			})
		end
	end

	-- Show selection UI
	vim.ui.select(items, {
		prompt = "Select a Todoist project:",
		format_item = function(item)
			local icon = item.data.is_favorite and "⭐ " or "📋 "
			return icon .. item.text
		end,
	}, function(selected)
		if selected then
			if config.is_debug() then
				print("DEBUG: User selected project:", selected.data.name)
				print("DEBUG: Opening project:", vim.inspect(selected.data))
			end

			-- Use buffer.lua to open the project
			local buffer = require("todoist.buffer")
			buffer.open_project(selected.data.id)
		end
	end)
end

-- Direct project opening function
function M.open_project(project_id)
	if not config.is_valid(project_id) then
		vim.notify("Invalid project ID", vim.log.levels.ERROR)
		return
	end

	local buffer = require("todoist.buffer")
	buffer.open_project(project_id)
end

-- Utility functions for manual access
function M.sync_current_buffer()
	local buf = vim.api.nvim_get_current_buf()
	local buffer = require("todoist.buffer")
	local buffer_info = buffer.buffers[buf]

	if buffer_info then
		buffer.sync_buffer(buf)
	else
		vim.notify("Current buffer is not a Todoist project", vim.log.levels.WARN)
	end
end

function M.refresh_current_buffer()
	local buf = vim.api.nvim_get_current_buf()
	local buffer = require("todoist.buffer")
	local buffer_info = buffer.buffers[buf]

	if buffer_info then
		buffer.refresh_buffer(buf)
	else
		vim.notify("Current buffer is not a Todoist project", vim.log.levels.WARN)
	end
end

-- Debug function to check configuration
function M.debug_config()
	print("=== Todoist Configuration Debug ===")
	print("API Token:", config.get_token() and "SET" or "NOT SET")
	print("Debug mode:", config.is_debug())
	print("Config:", vim.inspect(config.get_config()))

	-- Test API connection
	if config.get_token() then
		local api = require("todoist.api")
		api.get_projects(function(result)
			if result.error then
				print("API Test FAILED:", result.error)
			else
				print("API Test SUCCESS: Found", #result.data, "projects")
			end
		end)
	else
		print("Cannot test API - no token configured")
	end
end

-- Setup commands
function M.setup_commands()
	vim.api.nvim_create_user_command("TodoistProjects", M.select_project, {
		desc = "Open Todoist project selector",
	})

	vim.api.nvim_create_user_command("TodoistSync", M.sync_current_buffer, {
		desc = "Sync current Todoist buffer",
	})

	vim.api.nvim_create_user_command("TodoistRefresh", M.refresh_current_buffer, {
		desc = "Refresh current Todoist buffer from server",
	})

	vim.api.nvim_create_user_command("TodoistOpen", function(opts)
		local project_id = opts.args
		if project_id and project_id ~= "" then
			M.open_project(project_id)
		else
			vim.notify("Usage: :TodoistOpen <project_id>", vim.log.levels.ERROR)
		end
	end, {
		nargs = 1,
		desc = "Open specific Todoist project by ID",
	})

	vim.api.nvim_create_user_command("TodoistDebug", M.debug_config, {
		desc = "Debug Todoist configuration and API connection",
	})
end

return M
