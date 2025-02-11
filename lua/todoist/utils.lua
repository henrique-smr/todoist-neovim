local M = {}

function M.append(list, ...)
	for _, v in ipairs({ ... }) do
		list[#list + 1] = v
	end
end

function M.create_project_buffer(content)
	local api = vim.api
	local buffer = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(buffer, 0, 0, true, content)
	vim.cmd("tab sb" .. buffer)
	vim.cmd("setfiletype markdown")
	api.nvim_set_option_value("conceallevel", 3, { scope = "local" })
	api.nvim_set_option_value("concealcursor", "inv", { scope = "local" })
	api.nvim_set_option_value("swapfile", false, { scope = "local" })
	api.nvim_set_option_value("buflisted", false, { scope = "local" })
	api.nvim_set_option_value("cursorcolumn", false, { scope = "local" })
	api.nvim_set_option_value("cursorline", false, { scope = "local" })
	api.nvim_set_option_value("spell", false, { scope = "local" })
	api.nvim_set_option_value("autoindent", false, { scope = "local" })
	api.nvim_set_option_value("expandtab", false, { scope = "local" })
	api.nvim_set_option_value("tabstop", 4, { scope = "local" })
	api.nvim_set_option_value("shiftwidth", 4, { scope = "local" })
	api.nvim_set_option_value("modifiable", false, { scope = "local" })
	api.nvim_set_option_value("breakindent", true, { scope = "local" })
	vim.cmd('sy region HID start="{%" end="}" conceal')
	return buffer
end

function M.ts_query_md_tasks(buf)
	-- Get the language tree for the buffer
	local lang_tree = vim.treesitter.get_parser(buf, "markdown")
	-- local syntax_tree = lang_tree:parse({ cursor_pos[1] - 1, cursor_pos[1] - 1 })
	local syntax_tree = lang_tree:parse()
	local root = syntax_tree[1]:root()

	return vim.treesitter.query.parse(
		"markdown",
		[[
		[
			(list_item
				(task_list_marker_checked) @task_checked)
			(list_item
				(task_list_marker_unchecked) @task_unchecked) ]
		]]
	),
		root
end

function M.buf_toggle_task_list_item()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)

	local query, root = M.ts_query_md_tasks(bufnr)

	-- Traverse the tree to find a task_list_marker on the current line
	for _, node in query:iter_captures(root, bufnr, cursor_pos[1] - 1, cursor_pos[1]) do
		local start_row, start_col, _, end_col = node:range()
		-- Check if the node is a list_item and contains a task_list_marker
		if node:type() == "task_list_marker_unchecked" then
			local line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
			local new_checkbox = "[x]"

			local new_line = line:sub(1, start_col) .. new_checkbox .. line:sub(end_col + 1)
			vim.api.nvim_buf_set_lines(bufnr, start_row, start_row + 1, false, { new_line })
			local id = line:match("{%%item/(.*)}")
			return "checked", id
		end
		if node:type() == "task_list_marker_checked" then
			local line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
			local new_checkbox = "[ ]"

			local new_line = line:sub(1, start_col) .. new_checkbox .. line:sub(end_col + 1)
			vim.api.nvim_buf_set_lines(bufnr, start_row, start_row + 1, false, { new_line })
			local id = line:match("{%%item/(.*)}")
			return "unchecked", id
		end
	end
	return nil, nil
end

function M.buf_next_task()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row = cursor_pos[1] - 1 -- Lua uses 0-based indexing for rows

	local query, root = M.ts_query_md_tasks(bufnr)

	for _, node in query:iter_captures(root, bufnr, row, -1) do
		if node:type() == "task_list_marker_unchecked" or node:type() == "task_list_marker_checked" then
			local start_row, start_col = node:range()
			if row < start_row then
				vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col + 1 })
				break
			end
		end
	end
end
function M.buf_prev_task()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local row = cursor_pos[1] - 1 -- Lua uses 0-based indexing for rows

	local query, root = M.ts_query_md_tasks(bufnr)

	local last_row, last_col
	for _, node in query:iter_captures(root, bufnr, 0, row) do
		if node:type() == "task_list_marker_unchecked" or node:type() == "task_list_marker_checked" then
			local start_row, start_col = node:range()
			if row > start_row then
				last_row, last_col = start_row + 1, start_col + 1
			end
		end
	end
	if last_row then
		vim.api.nvim_win_set_cursor(0, { last_row, last_col })
	end
end

return M
