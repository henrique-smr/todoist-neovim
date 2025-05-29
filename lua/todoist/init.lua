local M = {
	_show_completed = false,
}

local client = require("todoist.sync-client")
local u = require("todoist.utils")

function M.setup(opts)
	assert(opts and opts.token, "Token deve ser definido")

	M.nid = vim.api.nvim_create_namespace("todoist-neovim")
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
local function make_item(opts)
	table.insert(opts.content, "")

	local check_box = opts.item.completed_at ~= vim.NIL and "- [x]" or "- [ ]"

	table.insert(
		opts.content,
		string.rep("\t", opts.depth) .. check_box .. " " .. opts.item.content .. " {%item/" .. opts.item.id .. "}"
	)
	local start_row = #opts.content

	if #opts.item.description > 0 then
		table.insert(opts.content, "")
		local description_lines = vim.split(opts.item.description, "\n", { trimempty = true })
		for _, description_line in ipairs(description_lines) do
			if #description_line > 0 then
				table.insert(opts.content, string.rep("\t", opts.depth + 1) .. description_line)
			else
				table.insert(opts.content, string.rep("\t", opts.depth + 1))
			end
		end
	end
	local end_row = #opts.content

	opts.metadata.items[opts.item.id] = { range = { start_row, end_row }, item = opts.item }

	for _, sub_item in ipairs(opts.items_list) do
		if sub_item.parent_id == opts.item.id then
			make_item({
				content = opts.content,
				item = sub_item,
				items_list = opts.items_list,
				metadata = opts.metadata,
				depth = opts.depth + 1,
			})
		end
	end

	table.insert(opts.content, "")
end

function M.open_project(project_id)
	local projects = M.store:get("projects")
	local sections = M.store:get("sections")
	local items = M.store:get("items")

	local _metadata = {
		projects = {},
		sections = {},
		items = {},
		items_by_marks = {},
	}

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

	_metadata.projects[project.id] = { range = { #content, #content } }

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
			make_item({
				content = content,
				item = item,
				depth = 0,
				metadata = _metadata,
				items_list = project_items,
			})
		end
	end
	for _, section in ipairs(project_sections) do
		table.insert(content, "")
		table.insert(content, "## " .. section.name .. " {%section/" .. section.id .. "}")

		_metadata.sections[section.id] = { range = { #content, #content } }

		for _, item in pairs(items) do
			if item.section_id == section.id and item.parent_id == vim.NIL then
				make_item({
					content = content,
					item = item,
					depth = 0,
					metadata = _metadata,
					items_list = project_items,
				})
			end
		end
	end

	local buffer = u.create_project_buffer(content)
	local api = vim.api

	for id, o in pairs(_metadata.items) do
		local ext_id = api.nvim_buf_set_extmark(buffer, M.nid, o.range[1] - 1, 0, {
			virt_text = { { "(" .. id .. ")", "Comment" } },
			virt_text_pos = "eol",
			end_row = o.range[2],
			invalidate = true,
			undo_restore = true,
			virt_text_hide = true,
		})
		_metadata.items_by_marks[ext_id] = o.item
	end

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
			local status = u.buf_toggle_task_list_item()
			vim.api.nvim_set_option_value("modifiable", false, { scope = "local" })
			local mark = u.get_mark_at_line(M.nid)
			if status == "checked" and mark then
				local item_id = _metadata.items_by_marks[mark[1]].id
				client.complete_item(item_id)
			elseif status == "unchecked" and mark then
				local item_id = _metadata.items_by_marks[mark[1]].id
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
	api.nvim_buf_set_keymap(buffer, "n", "&", "", {
		noremap = true,
		nowait = true,
		callback = function()
			local mark = u.get_mark_at_line(M.nid)
			-- -- local text = ms[1][3].virt_text
			print(vim.inspect(_metadata.items_by_marks[mark[1]]))
		end,
	})
end

return M
