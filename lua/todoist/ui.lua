-- UI components
local M = {}

local config = require('todoist.config')

function M.show_project_list(projects, on_select)
  local items = {}
  for _, project in ipairs(projects) do
    if config.is_valid(project) and config.is_valid(project.name) then
      table.insert(items, project.name)
    end
  end
  
  if config.is_debug() then
    print("DEBUG: Showing project list with", #items, "projects")
  end
  
  vim.schedule(function()
    vim.ui.select(items, {
      prompt = "Select a project:",
      format_item = function(item)
        return "📁 " .. item
      end,
    }, function(choice)
      if config.is_valid(choice) then
        if config.is_debug() then
          print("DEBUG: User selected project:", choice)
        end
        vim.schedule(function()
          on_select(choice)
        end)
      end
    end)
  end)
end

function M.show_error(message)
  vim.schedule(function()
    vim.notify(message, vim.log.levels.ERROR)
  end)
end

function M.show_info(message)
  vim.schedule(function()
    vim.notify(message, vim.log.levels.INFO)
  end)
end

return M