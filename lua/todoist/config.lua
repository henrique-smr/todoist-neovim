-- Centralized configuration management
local M = {}

-- Default configuration
local default_config = {
	api_token = nil,
	auto_sync = true,
	sync_interval = 30000, -- 30 seconds
	debug = false,
}

-- Current configuration
local current_config = vim.deepcopy(default_config)

-- Setup configuration
function M.setup(opts)
	current_config = vim.tbl_deep_extend("force", current_config, opts or {})

	if current_config.debug then
		print("DEBUG: Config setup complete:", vim.inspect(current_config))
	end
end

-- Get configuration value
function M.get(key)
	if key then
		return current_config[key]
	end
	return current_config
end

-- Set configuration value
function M.set(key, value)
	current_config[key] = value
end

-- Check if debug mode is enabled
function M.is_debug()
	return current_config.debug == true
end

-- Get API token
function M.get_token()
	return current_config.api_token
end

-- Get auto sync setting
function M.get_auto_sync()
	return current_config.auto_sync
end

-- Get sync interval
function M.get_sync_interval()
	return current_config.sync_interval
end

return M
