-- Todoist.nvim - A Neovim plugin for Todoist integration with markdown
-- Author: AI Assistant
-- License: MIT

local M = {}

-- Load modules
local config = require('todoist.config')
local api = require('todoist.api')
local parser = require('todoist.parser')
local sync = require('todoist.sync')
local ui = require('todoist.ui')

-- Internal state
local projects = {}
local current_project = nil
local sync_timer = nil
local ns_id = vim.api.nvim_create_namespace("todoist")

-- Setup function
function M.setup(opts)
  config.setup(opts)
  
  if not config.is_valid(config.get_token()) then
    vim.notify("Todoist API token not provided. Please set it in your config.", vim.log.levels.ERROR)
    return
  end
  
  api.set_token(config.get_token())
  
  -- Create user commands
  vim.api.nvim_create_user_command('TodoistProjects', M.list_projects, {})
  vim.api.nvim_create_user_command('TodoistCreateProject', function(opts)
    M.create_project(opts.args)
  end, { nargs = 1 })
  vim.api.nvim_create_user_command('TodoistOpen', function(opts)
    M.open_project(opts.args)
  end, { nargs = 1, complete = M.complete_projects })
  vim.api.nvim_create_user_command('TodoistSync', M.sync_current_buffer, {})
  vim.api.nvim_create_user_command('TodoistToggle', M.toggle_task, {})
  
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
      if bufname:match("%.todoist%.md$") then
        vim.keymap.set({'n', 'i'}, '<C-t>', M.toggle_task, { buffer = true })
        vim.keymap.set('n', '<leader>ts', M.sync_current_buffer, { buffer = true })
      end
    end,
  })
  
  if config.is_debug() then
    print("DEBUG: Todoist.nvim setup completed")
  end
end

-- List all projects
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
    ui.show_project_list(projects, M.open_project)
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

-- Open a project as markdown
function M.open_project(project_name)
  local project = nil
  for _, p in ipairs(projects) do
    if config.is_valid(p.name) and p.name == project_name then
      project = p
      break
    end
  end
  
  if not project then
    vim.notify("Project not found: " .. project_name, vim.log.levels.ERROR)
    return
  end
  
  current_project = project
  
  if config.is_debug() then
    print("DEBUG: Opening project:", vim.inspect(project))
  end
  
  -- Get project data with tasks and sections
  api.get_project_data(project.id, function(result)
    if result.error then
      vim.notify("Error fetching project data: " .. result.error, vim.log.levels.ERROR)
      return
    end
    
    -- Add project info to the data
    result.data.project = project
    
    if config.is_debug() then
      print("DEBUG: Project data received:", vim.inspect(result.data))
    end
    
    local filename = project.name:gsub("[^%w%s%-_]", "") .. ".todoist.md"
    local filepath = vim.fn.expand("~/todoist/" .. filename)
    
    -- Ensure directory exists
    vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")
    
    -- Create buffer
    local buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(buf, filepath)
    
    -- Generate markdown content
    local content = parser.project_to_markdown(result.data)
    
    if config.is_debug() then
      print("DEBUG: Generated markdown lines:", vim.inspect(content.lines))
      print("DEBUG: Generated extmarks:", vim.inspect(content.extmarks))
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content.lines)
    
    -- Open buffer in current window first
    vim.api.nvim_set_current_buf(buf)
    vim.bo.filetype = "markdown"
    vim.bo.modified = false
    
    -- Set extmarks for tracking AFTER the buffer is current
    vim.schedule(function()
      parser.set_extmarks(buf, ns_id, content.extmarks)
      
      if config.is_debug() then
        local test_extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
        print("DEBUG: Extmarks set successfully, count:", #test_extmarks)
      end
    end)
    
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
  
  if config.is_debug() then
    print("DEBUG: Syncing buffer with", #lines, "lines and", #extmarks, "extmarks")
    if #extmarks > 0 then
      print("DEBUG: First extmark:", vim.inspect(extmarks[1]))
    end
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

-- Toggle task completion
function M.toggle_task()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1] - 1
  
  -- Find extmark for current line or nearby lines
  local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 
    { line_num - 2, 0 }, { line_num + 2, -1 }, { details = true })
  
  local task_extmark = nil
  for _, mark in ipairs(extmarks) do
    local data = mark[4]
    if config.is_valid(data) and data.todoist_type == "task" then
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
  
  -- Update extmark data immediately
  local is_completed = new_line:match("%- %[x%]") ~= nil
  local existing_opts = vim.deepcopy(task_extmark[4])
  existing_opts.todoist_completed = is_completed
  
  pcall(function()
    vim.api.nvim_buf_set_extmark(buf, ns_id, line_num, 0, existing_opts)
  end)
  
  -- Sync with Todoist API
  api.toggle_task(task_id, is_completed, function(result)
    if result.error then
      vim.notify("Error toggling task: " .. result.error, vim.log.levels.ERROR)
      -- Revert the change
      vim.api.nvim_buf_set_lines(buf, line_num, line_num + 1, false, { current_line })
      existing_opts.todoist_completed = not is_completed
      pcall(function()
        vim.api.nvim_buf_set_extmark(buf, ns_id, line_num, 0, existing_opts)
      end)
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
  sync_timer:start(config.get_sync_interval(), config.get_sync_interval(), vim.schedule_wrap(function()
    local buf = vim.api.nvim_get_current_buf()
    local bufname = vim.api.nvim_buf_get_name(buf)
    
    if bufname:match("%.todoist%.md$") and not vim.bo.modified then
      M.sync_current_buffer()
    end
  end))
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
    if config.is_valid(project.name) and project.name:lower():find(arg_lead:lower(), 1, true) then
      table.insert(matches, project.name)
    end
  end
  return matches
end

-- Get namespace ID (for external access)
function M.get_namespace_id()
  return ns_id
end

return M