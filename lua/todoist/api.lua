-- Todoist API client
local M = {}

local curl = require("plenary.curl")
local json = vim.json

M.base_url = "https://api.todoist.com/rest/v2"
M.token = nil

function M.set_token(token)
	M.token = token
end

local function make_request(method, endpoint, data, callback)
	if not M.token then
		callback({ error = "API token not set" })
		return
	end

	local headers = {
		["Authorization"] = "Bearer " .. M.token,
		["Content-Type"] = "application/json",
	}

	local url = M.base_url .. endpoint
	local opts = {
		method = method,
		url = url,
		headers = headers,
		callback = function(response)
			if response.status >= 200 and response.status < 300 then
				local success, data = pcall(json.decode, response.body)
				if success then
					callback({ data = data })
				else
					callback({ error = "Failed to parse JSON response" })
				end
			else
				callback({ error = "HTTP " .. response.status .. ": " .. (response.body or "Unknown error") })
			end
		end,
	}

	if data then
		opts.body = json.encode(data)
	end

	curl.request(opts)
end

function M.get_projects(callback)
	make_request("GET", "/projects", nil, callback)
end

function M.create_project(name, callback)
	make_request("POST", "/projects", { name = name }, callback)
end

function M.get_project_data(project_id, callback)
	local scheduled_callback = vim.schedule_wrap(callback)
	-- Get tasks for the project
	make_request("GET", "/tasks?project_id=" .. project_id, nil, function(tasks_result)
		if tasks_result.error then
			scheduled_callback(tasks_result)
			return
		end

		-- Get sections for the project
		make_request("GET", "/sections?project_id=" .. project_id, nil, function(sections_result)
			if sections_result.error then
				scheduled_callback(sections_result)
				return
			end

			scheduled_callback({
				data = {
					project_id = project_id,
					tasks = tasks_result.data or {},
					sections = sections_result.data or {},
				},
			})
		end)
	end)
end

function M.create_task(project_id, content, section_id, parent_id, callback)
	local data = {
		project_id = project_id,
		content = content,
	}

	if section_id then
		data.section_id = section_id
	end

	if parent_id then
		data.parent_id = parent_id
	end

	make_request("POST", "/tasks", data, callback)
end

function M.update_task(task_id, content, callback)
	make_request("POST", "/tasks/" .. task_id, { content = content }, callback)
end

function M.delete_task(task_id, callback)
	make_request("DELETE", "/tasks/" .. task_id, nil, callback)
end

function M.toggle_task(task_id, is_completed, callback)
	if is_completed then
		make_request("POST", "/tasks/" .. task_id .. "/close", nil, callback)
	else
		make_request("POST", "/tasks/" .. task_id .. "/reopen", nil, callback)
	end
end

function M.create_section(project_id, name, callback)
	make_request("POST", "/sections", { project_id = project_id, name = name }, callback)
end

function M.update_section(section_id, name, callback)
	make_request("POST", "/sections/" .. section_id, { name = name }, callback)
end

function M.delete_section(section_id, callback)
	make_request("DELETE", "/sections/" .. section_id, nil, callback)
end

return M
