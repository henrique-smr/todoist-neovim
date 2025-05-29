-- UI components
local M = {}

function M.show_project_list(projects, on_select)
	local items = {}
	for _, project in ipairs(projects) do
		table.insert(items, project.name)
	end

	vim.schedule(function()
		vim.ui.select(items, {
			prompt = "Select a project:",
			format_item = function(item)
				return "📁 " .. item
			end,
		}, function(choice)
			if choice then
				on_select(choice)
			end
		end)
	end)
end

function M.show_error(message)
	vim.notify(message, vim.log.levels.ERROR)
end

function M.show_info(message)
	vim.notify(message, vim.log.levels.INFO)
end

return M
