local Store = {
	_data = {},
	_file_path = "~/.todoist-nvim.store.json",
}

function Store:new(opts)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	if opts then
		if opts.file_path then
			o._file_path = opts.file_path
		end
	end
	o._file_path = vim.fn.fnamemodify(o._file_path, ":p")
	return o
end

function Store:from_file()
	local file = io.open(self._file_path, "r")
	if file then
		local data = vim.json.decode(file:read("*all"))
		if data then
			self:upsert(data)
		else
			print("Error: Failed to decode JSON data")
		end
		file:close()
		return true
	end
	return false
end

function Store:to_file()
	local file = io.open(self._file_path, "w")
	if file then
		local json_data = vim.json.encode(self._data)
		file:write(json_data)
		file:close()
		return true
	end

	-- vim.fn.writefile({ vim.json.encode(self._data) }, self._file_path)

	-- if file then
	-- 	local json_data = vim.json.encode(self._data)
	-- 	file:write(json_data)
	-- 	file:close()
	-- 	return true
	-- end
	return false
end

function Store:upsert(data)
	self._data = vim.tbl_deep_extend("force", self._data, data)
	self:to_file()
end

function Store:get(...)
	local args = { ... }
	local curr = self._data
	for _, key in ipairs(args) do
		curr = curr[key]
		if curr == nil then
			return nil
		end
	end
	return curr
end

function Store:print()
	print(vim.inspect(self._data))
end

return Store
