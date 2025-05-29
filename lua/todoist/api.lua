-- Todoist API client
local M = {}

local curl = require("plenary.curl")
local json = vim.json
local config = require("todoist.config")

M.base_url = "https://api.todoist.com/rest/v2"
M.token = nil

function M.set_token(token)
	M.token = token
end

local function make_request(method, endpoint, data, callback)
	if not config.is_valid(M.token) then
		vim.schedule(function()
			callback({ error = "API token not set" })
		end)
		return
	end

	local headers = {
		["Authorization"] = "Bearer " .. M.token,
		["Content-Type"] = "application/json",
	}

	local url = M.base_url .. endpoint

	if config.is_debug() then
		print("DEBUG: Making API request:", method, url)
		if data then
			print("DEBUG: Request data:", vim.inspect(data))
		end
	end

	local opts = {
		method = method,
		url = url,
		headers = headers,
		callback = function(response)
			vim.schedule(function()
				if config.is_debug() then
					print("DEBUG: API response status:", response.status)
					if response.body and response.body ~= "" then
						print("DEBUG: API response body:", response.body)
					else
						print("DEBUG: API response body: (empty)")
					end
				end

				if response.status >= 200 and response.status < 300 then
					-- Handle empty responses (like 204 No Content)
					if not response.body or response.body == "" then
						callback({ data = {} })
					else
						local success, parsed_data = pcall(json.decode, response.body)
						if success then
							callback({ data = parsed_data })
						else
							callback({ error = "Failed to parse JSON response: " .. (response.body or "") })
						end
					end
				else
					callback({ error = "HTTP " .. response.status .. ": " .. (response.body or "Unknown error") })
				end
			end)
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
	-- Get tasks for the project
	make_request("GET", "/tasks?project_id=" .. project_id, nil, function(tasks_result)
		if tasks_result.error then
			vim.schedule(function()
				callback(tasks_result)
			end)
			return
		end

		-- Get sections for the project
		make_request("GET", "/sections?project_id=" .. project_id, nil, function(sections_result)
			if sections_result.error then
				vim.schedule(function()
					callback(sections_result)
				end)
				return
			end

			vim.schedule(function()
				callback({
					data = {
						project_id = project_id,
						tasks = tasks_result.data or {},
						sections = sections_result.data or {},
					},
				})
			end)
		end)
	end)
end

function M.create_task(project_id, content, section_id, parent_id, description, callback)
	local data = {
		project_id = project_id,
		content = content,
	}

	if config.is_valid(section_id) then
		data.section_id = section_id
	end

	if config.is_valid(parent_id) then
		data.parent_id = parent_id
	end

	if config.is_valid(description) and description ~= "" then
		data.description = description
	end

	make_request("POST", "/tasks", data, callback)
end

function M.update_task(task_id, content, description, callback)
	local data = { content = content }

	if config.is_valid(description) then
		data.description = description
	else
		data.description = ""
	end

	make_request("POST", "/tasks/" .. task_id, data, callback)
end

function M.delete_task(task_id, callback)
	make_request("DELETE", "/tasks/" .. task_id, nil, callback)
end

function M.toggle_task(task_id, is_completed, callback)
	if config.is_debug() then
		print("DEBUG: Toggling task", task_id, "to completed:", is_completed)
	end

	if is_completed then
		make_request("POST", "/tasks/" .. task_id .. "/close", nil, callback)
	else
		make_request("POST", "/tasks/" .. task_id .. "/reopen", nil, callback)
	end
end

-- Get current task state to avoid redundant toggles
function M.get_task(task_id, callback)
	make_request("GET", "/tasks/" .. task_id, nil, callback)
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
