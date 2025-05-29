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
