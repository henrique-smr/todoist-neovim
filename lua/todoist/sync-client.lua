local M = {}

local u = require("todoist.utils")

---@class SyncOpts
---@field params table<string,any>
---@field token string
---@field op string

---Sync API do Todoist
---@param opts SyncOpts
---@return table|nil
local function request_sync_todoist(opts)
	local token = opts.token
	local params = opts.params
	local op = opts.op
	local base_url = "https://api.todoist.com/sync/v9/" .. op
	local headers = {
		"Authorization: Bearer " .. token,
	}
	local cmd = {}
	u.append(cmd, "curl", base_url)
	for _, value in ipairs(headers) do
		u.append(cmd, "-H", value)
	end
	for key, value in pairs(params) do
		if type(value) ~= "string" then
			value = vim.json.encode(value)
		end
		u.append(cmd, "-d", key .. "=" .. value)
	end
	local resp = vim.system(cmd, { text = true }):wait(5000)
	if resp.code ~= 0 then
		print("Error: " .. resp.stderr)
		return nil
	end
	local s, data = pcall(vim.json.decode, resp.stdout)
	if not s then
		print("Error: Failed to decode JSON data: " .. data)
		return nil
	end
	return data
end

function M.sync(sync_token, resources)
	return request_sync_todoist({
		op = "sync",
		token = M.token,
		params = {
			sync_token = sync_token,
			resource_types = resources,
		},
	})
end

function M.get_all_completed(params)
	return request_sync_todoist({
		op = "completed/get_all",
		token = M.token,
		params = params,
	})
end

function M.complete_item(item_id)
	local uuid = vim.system({ "uuidgen" }, { text = true }):wait()
	if uuid.code ~= 0 then
		vim.notify("missing dependency: 'uuidgen'. Failed to generate UUID", vim.log.levels.ERROR)
		return nil
	end
	return request_sync_todoist({
		op = "sync",
		token = M.token,
		params = {
			commands = {
				{
					type = "item_close",
					uuid = uuid.stdout,
					args = {
						id = item_id,
					},
				},
			},
		},
	})
end
function M.uncomplete_item(item_id)
	local uuid = vim.system({ "uuidgen" }, { text = true }):wait()
	if uuid.code ~= 0 then
		vim.notify("missing dependency: 'uuidgen'. Failed to generate UUID", vim.log.levels.ERROR)
		return nil
	end
	return request_sync_todoist({
		op = "sync",
		token = M.token,
		params = {
			commands = {
				{
					type = "item_uncomplete",
					uuid = uuid.stdout,
					args = {
						id = item_id,
					},
				},
			},
		},
	})
end

function M.init(opts)
	M.token = opts.token
end

return M
