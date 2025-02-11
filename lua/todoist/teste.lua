vim.api.nvim_create_user_command("TesteTaskFinder", function()
	-- Get the current buffer and cursor position
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)

	-- Get the language tree for the buffer
	local lang_tree = vim.treesitter.get_parser(bufnr, "markdown")
	local syntax_tree = lang_tree:parse({ cursor_pos[1] - 1, cursor_pos[1] - 1 })
	local root = syntax_tree[1]:root()

	-- Get the smallest node that contains the current line
	local query = vim.treesitter.query.parse(
		"markdown",
		[[
		[
			(list_item
				(task_list_marker_checked) @task_checked)
			(list_item
				(task_list_marker_unchecked) @task_unchecked) ]
		]]
	)
	local found_task = false

	-- Traverse the tree to find a task_list_marker on the current line
	for _, node in query:iter_captures(root, bufnr, cursor_pos[1] - 1, cursor_pos[1]) do
		print(node:type())
		-- Check if the node is a list_item and contains a task_list_marker
		if node:type() == "task_list_marker_unchecked" or node:type() == "task_list_marker_checked" then
			found_task = true
		end
	end

	print(found_task)
end, {})
