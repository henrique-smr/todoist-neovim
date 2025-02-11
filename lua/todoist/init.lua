local M = {
	_show_completed = false,
}

local client = require("todoist.sync-client")
local u = require("todoist.utils")

function M.setup(opts)
	assert(opts and opts.token, "Token deve ser definido")
	M.store = require("todoist.store"):new()
	M.store:from_file()
	client.init({
		token = opts.token, --"169bf39fb2bb874dd11b7f66d061bcad15023b81",
	})
	vim.api.nvim_create_user_command("TodoistSync", function()
		M.sync()
	end, {})
	vim.api.nvim_create_user_command("TodoistFullSync", function()
		M.sync({ full_sync = true })
	end, {})
	vim.api.nvim_create_user_command("TodoistFindProjects", function()
		M.find_projects()
	end, {})
	vim.api.nvim_create_user_command("TodoistAddTask", function()
		M.add_item({})
	end, {})
end

function M.sync(opts)
	local sync_token = (opts and opts.full_sync) and "*" or M.store:get("sync_token") or "*"

	local data = client.sync(sync_token, {
		"projects",
		"items",
		"sections",
	})
	if data == nil then
		return
	end

	local store_data = {
		projects = {},
		items = {},
		sections = {},
	}

	for _, proj in pairs(data.projects) do
		store_data.projects[proj.id] = proj
	end
	for _, item in pairs(data.items) do
		store_data.items[item.id] = item
	end
	for _, section in pairs(data.sections) do
		store_data.sections[section.id] = section
	end

	for _, proj in ipairs(data.projects) do
		local completed_data = client.get_all_completed({
			project_id = proj.id,
			annotate_items = true,
		})
		if completed_data ~= nil then
			for _, item in ipairs(completed_data.items) do
				store_data.items[item.task_id] = item.item_object
			end
		end
	end
	-- print(vim.inspect(store_data))
	M.store:upsert(store_data)
end

function M.find_projects()
	local projects = M.store:get("projects")
	if projects == nil then
		return {}
	end

	local fzf_lua = require("fzf-lua")

	local items = {}
	for _, proj in pairs(projects) do
		table.insert(items, proj)
	end
	table.sort(items, function(a, b)
		return a.child_order < b.child_order
	end)
	local content = {}
	for _, proj in ipairs(items) do
		table.insert(content, proj.name .. "\t\t" .. proj.id)
	end

	fzf_lua.fzf_exec(content, {
		prompt = "Select a project",
		fzf_opts = {
			["-d"] = "\t\t",
			["--with-nth"] = "1",
		},
		actions = {
			["default"] = {
				function(selected)
					local selected_id = selected[1]:match("[^\t\t]+$")
					vim.api.nvim_win_close(0, true)
					M.open_project(selected_id)
				end,
			},
		},
	})
end

function M.add_item(opts)
	local project_id = opts.project_id
	local section_id = opts.section_id
	local parent_id = opts.parent_id
	local content = vim.fn.input("Enter the task content: ")
	local description = vim.fn.input("Enter the task description: ")
end

function M.open_project(project_id)
	local projects = M.store:get("projects")
	local sections = M.store:get("sections")
	local items = M.store:get("items")
	local project
	for _, proj in pairs(projects) do
		if proj.id == project_id then
			project = proj
			break
		end
	end

	local project_sections = {}
	for _, section in pairs(sections) do
		if section.project_id == project_id then
			table.insert(project_sections, section)
		end
	end

	local project_items = {}
	for _, item in pairs(items) do
		if item.project_id == project_id and item.section_id == vim.NIL then
			table.insert(project_items, item)
		end
	end

	local content = {
		"# " .. project.name .. " {%project/" .. project.id .. "}",
	}
	local function make_item(item)
		table.insert(content, "")
		local check_box = item.completed_at ~= vim.NIL and "- [x]" or "- [ ]"
		table.insert(content, check_box .. " " .. item.content .. " {%item/" .. item.id .. "}")
		if #item.description > 0 then
			table.insert(content, "")
			local description_lines = vim.split(item.description, "\n", { trimempty = true })
			for _, description_line in ipairs(description_lines) do
				if #description_line > 0 then
					table.insert(content, "\t *" .. description_line .. "*")
				else
					table.insert(content, "\t")
				end
			end
			-- table.insert(content, "")
		end
		for _, sub_item in ipairs(project_items) do
			if sub_item.parent_id == item.id then
				table.insert(content, "")
				local sub_check_box = sub_item.completed_at ~= vim.NIL and "- [x]" or "- [ ]"
				table.insert(
					content,
					"\t" .. sub_check_box .. " " .. sub_item.content .. " {%item/" .. sub_item.id .. "}"
				)
				if #sub_item.description > 0 then
					table.insert(content, "")
					local description_lines = vim.split(sub_item.description, "\n", { trimempty = true })
					for _, description_line in ipairs(description_lines) do
						if #description_line > 0 then
							table.insert(content, "\t\t *" .. description_line .. "*")
						else
							table.insert(content, "\t\t")
						end
					end
					-- table.insert(content, "")
				end
			end
		end
		table.insert(content, "")
	end
	table.sort(project_items, function(a, b)
		return a.child_order < b.child_order
	end)
	if not M._show_completed then
		for i = #project_items, 1, -1 do
			local item = project_items[i]
			if item.completed_at ~= vim.NIL then
				table.remove(project_items, i)
			end
		end
	end
	table.sort(project_sections, function(a, b)
		return a.section_order < b.section_order
	end)
	for _, item in ipairs(project_items) do
		if item.parent_id == vim.NIL then
			make_item(item)
		end
	end
	for _, section in ipairs(project_sections) do
		table.insert(content, "")
		table.insert(content, "## " .. section.name .. " {%section/" .. section.id .. "}")
		for _, item in pairs(items) do
			if item.section_id == section.id and item.parent_id == vim.NIL then
				make_item(item)
			end
		end
	end

	local buffer = u.create_project_buffer(content)
	local api = vim.api

	api.nvim_buf_set_keymap(buffer, "n", "q", "", {
		noremap = true,
		callback = function()
			api.nvim_buf_delete(buffer, { force = true })
		end,
	})
	api.nvim_buf_set_keymap(buffer, "n", "<cr>", "", {
		noremap = true,
		callback = function()
			vim.api.nvim_set_option_value("modifiable", true, { scope = "local" })
			local status, item_id = u.buf_toggle_task_list_item()
			vim.api.nvim_set_option_value("modifiable", false, { scope = "local" })
			if status == "checked" then
				client.complete_item(item_id)
			elseif status == "unchecked" then
				client.uncomplete_item(item_id)
			end
		end,
	})
	api.nvim_buf_set_keymap(buffer, "n", "<tab>", "", {
		noremap = true,
		nowait = true,
		callback = function()
			u.buf_next_task()
		end,
	})
	api.nvim_buf_set_keymap(buffer, "n", "<S-tab>", "", {
		noremap = true,
		nowait = true,
		callback = function()
			u.buf_prev_task()
		end,
	})
end

return M
