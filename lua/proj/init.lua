local NuiPopup = require('nui.popup')
local NuiTable = require('nui.table')
local NuiLayout = require('nui.layout')
local NuiLine = require('nui.line')
local NuiText = require('nui.text')

local exclude_dirs = {}

local M = {}

---@class UnityProjInfo
---@field editor_version string
---@field company_name string|nil
---@field product_name string|nil

---@class BazelProjInfo
---@field module_name string|nil
---@field module_version string|nil

---@class ProjInfo
---@field dir string
---@field name string|nil
---@field description string[]
---@field icon string
---@field version string|nil
---@field unity UnityProjInfo|nil
---@field bazel BazelProjInfo|nil

---@param p string
---@return boolean
local function file_exists(p)
	local f = io.open(p, "r")
	if f == nil then
		return false
	else
		io.close(f)
		return true
	end
end

---@param p string
---@return boolean
local function dir_exists(p)
	return vim.fn.isdirectory(p) == 1
end

---@param p string
---@return boolean
local function exists(p)
	return file_exists(p) or dir_exists(p)
end

local function extract_readme_description(dir)
	local readme_path = vim.fs.joinpath(dir, "README.md")
	local readme = io.open(readme_path, 'r')
	if readme ~= nil then
		local description = {}
		local past_title = false
		for line in readme:lines('L') do
			local trimmed_line = vim.trim(line)
			if #trimmed_line > 0 then
				if string.sub(trimmed_line, 1, 1) == '#' then
					if past_title then break end
					past_title = true
				elseif past_title then
					table.insert(description, trimmed_line .. '\n')
				end
			else
				table.insert(description, '\n')
			end
		end
		io.close(readme)
		return description
	end
	return {}
end


---@param opts {callback: fun(stdout:string)}
local function spawn_and_read(cmd, opts)
	local stdout = vim.uv.new_pipe()
	local stdout_str = ""
	vim.uv.spawn(cmd, {
		cwd = opts.cwd,
		hide = true,
		stdio = { nil, stdout, nil },
		args = opts.args,
	}, function(code, signal)
		opts.callback(stdout_str)
	end)

	vim.uv.read_start(stdout, function(err, data)
		assert(not err, err)
		if data then
			stdout_str = stdout_str .. data
		end
	end)
end

local PROJ_TYPE = {
	BAZEL = "bazel",
	CMAKE = "cmake",
	RUST = "rust",
	ZIG = "zig",
	UNITY = "unity",
	UNREAL = "unreal",
	GIT = "git",
	GODOT = "godot",
	NEOVIM_PLUGIN = "neovim",
}

local PROJ_ICONS = {
	[PROJ_TYPE.BAZEL] = "",
	[PROJ_TYPE.UNITY] = "󰚯",
	[PROJ_TYPE.UNREAL] = "󰦱",
	[PROJ_TYPE.ZIG] = "",
	[PROJ_TYPE.RUST] = "",
	[PROJ_TYPE.CMAKE] = "󰔷",
	[PROJ_TYPE.GODOT] = "",
	[PROJ_TYPE.NEOVIM_PLUGIN] = "",
}

local default_info_table = {
	icon    = "",
	name    = nil,
	version = nil,
}

local proj_info_builders = {}

---@param builder fun(type:string, builder:fun(dir:string, cb: fun(info:any)))
function M.register_proj_info_builder(type, builder)
	proj_info_builders[type] = builder
end

M.register_proj_info_builder(PROJ_TYPE.BAZEL, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		icon = "",
		name = vim.fs.basename(dir),
		description = extract_readme_description(dir),
	})

	pcall(cb, info)

	spawn_and_read("buildozer", {
		cwd = dir,
		args = {
			"print name version",
			"//MODULE.bazel:%module",
		},
		callback = function(stdout)
			local o = vim.split(vim.trim(stdout), ' ')
			local name = o[1]
			local version = o[2]

			info = vim.tbl_deep_extend('force', info, {
				version = version,
				name = name,
				bazel = {
					module_name = name,
					module_version = version,
				},
			})
			pcall(cb, info)
		end,
	})
end)

---@param keys string[]
local function extract_yaml_values(p, keys)
	local values = {}
	local f = io.open(p, 'r')
	if f ~= nil then
		for line in f:lines("l") do
			local colon_idx = string.find(line, ':')
			if colon_idx ~= nil then
				local key = vim.trim(string.sub(line, 1, colon_idx - 1))
				local value = vim.trim(string.sub(line, colon_idx + 1))

				for _, k in ipairs(keys) do
					if key == key then
						if values[key] ~= nil then break end
						values[key] = value
					end
				end

				if #keys == #values then
					break
				end
			end
		end
		io.close(f)
	end
	return values
end

---@param keys string[]
local function extract_ini_values(p, keys)
	local values = {}
	local f = io.open(p, 'r')
	if f ~= nil then
		for line in f:lines("l") do
			local colon_idx = string.find(line, '=')
			if colon_idx ~= nil then
				local key = vim.trim(string.sub(line, 1, colon_idx - 1))
				local value = vim.trim(string.sub(line, colon_idx + 1))

				for _, k in ipairs(keys) do
					if key == key then
						if values[key] ~= nil then break end
						values[key] = value
					end
				end

				if #keys == #values then
					break
				end
			end
		end
		io.close(f)
	end
	return values
end

M.register_proj_info_builder(PROJ_TYPE.UNITY, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		icon = "󰚯",
		name = vim.fs.basename(dir),
		unity = {},
	})

	local project_version = extract_yaml_values(
		vim.fs.joinpath(dir, "ProjectSettings", "ProjectVersion.txt"),
		{ "m_EditorVersion" }
	)
	local project_settings = extract_yaml_values(
		vim.fs.joinpath(dir, "ProjectSettings", "ProjectSettings.asset"),
		{ "companyName", "productName" }
	)

	if project_version.m_EditorVersion ~= nil then
		info.unity.editor_version = project_version.m_EditorVersion;
	end

	if project_settings.companyName ~= nil then
		info.unity.company_name = project_settings.companyName;
	end

	if project_settings.productName ~= nil then
		info.name = project_settings.productName
		info.unity.product_name = project_settings.productName;
	else
		info.name = vim.fs.basename(dir)
	end

	pcall(cb, info)
end)


M.register_proj_info_builder(PROJ_TYPE.GODOT, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		name = vim.fs.basename(dir),
		description = extract_readme_description(dir),
		godot = {},
	})

	local project_config = extract_ini_values(
		vim.fs.joinpath(dir, "project.godot"),
		{ "config/name" }
	)


	local project_metadata = extract_ini_values(
		vim.fs.joinpath(dir, ".godot/editor/project_metadata.cfg"),
		{ "executable_path" }
	)

	if project_config["config/name"] ~= nil then
		info.name = project_config["config/name"]
	end

	if project_metadata.executable_path ~= nil then
		info.godot.executable_path = project_metadata.executable_path
	end

	pcall(cb, info)
end)

M.register_proj_info_builder(PROJ_TYPE.UNREAL, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		icon = "󰦱",
		name = vim.fs.basename(dir),
		description = extract_readme_description(dir),
		unreal = {}
	})

	local default_game = extract_ini_values(
		vim.fs.joinpath(dir, "Config/DefaultGame.ini"),
		{ "ProjectName" }
	)

	if default_game.ProjectName ~= nil then
		info.name = default_game.ProjectName
		info.unreal.project_name = default_game.ProjectName
	end

	pcall(cb, info)
end)

M.register_proj_info_builder(PROJ_TYPE.CMAKE, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		icon = "󰔷",
		description = extract_readme_description(dir),
		name = vim.fs.basename(dir),
	})

	pcall(cb, info)
end)

M.register_proj_info_builder(PROJ_TYPE.RUST, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		icon = "",
		description = extract_readme_description(dir),
		name = vim.fs.basename(dir),
	})

	pcall(cb, info)
end)

M.register_proj_info_builder(PROJ_TYPE.ZIG, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		icon = "",
		description = extract_readme_description(dir),
		name = vim.fs.basename(dir),
	})

	pcall(cb, info)
end)

M.register_proj_info_builder(PROJ_TYPE.NEOVIM_PLUGIN, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		name = vim.fs.basename(dir),
		description = extract_readme_description(dir),
	})

	pcall(cb, info)
end)

M.register_proj_info_builder(PROJ_TYPE.GIT, function(dir, cb)
	local info = vim.tbl_deep_extend('force', default_info_table, {
		dir = dir,
		name = vim.fs.basename(dir),
		description = extract_readme_description(dir),
	})

	pcall(cb, info)
end)

function M.proj_icon(type)
	return PROJ_ICONS[type] or ""
end

---@param dir string
function M.proj_type(dir)
	if file_exists(vim.fs.joinpath(dir, "MODULE.bazel")) then
		return PROJ_TYPE.BAZEL
	end

	if file_exists(vim.fs.joinpath(dir, "CMakeLists.txt")) then
		return PROJ_TYPE.CMAKE
	end

	if file_exists(vim.fs.joinpath(dir, "Cargo.toml")) then
		return PROJ_TYPE.RUST
	end

	if file_exists(vim.fs.joinpath(dir, "build.zig")) then
		return PROJ_TYPE.ZIG
	end

	if file_exists(vim.fs.joinpath(dir, "project.godot")) then
		return PROJ_TYPE.GODOT
	end

	if file_exists(vim.fs.joinpath(dir, "ProjectSettings", "ProjectVersion.txt")) then
		return PROJ_TYPE.UNITY
	end

	if file_exists(vim.fs.joinpath(dir, vim.fs.basename(dir) .. ".uproject")) then
		return PROJ_TYPE.UNREAL
	end

	if dir:sub(- #".nvim") == ".nvim" or (file_exists(vim.fs.joinpath(dir, "vim.toml")) and dir_exists(vim.fs.joinpath(dir, "lua"))) then
		return PROJ_TYPE.NEOVIM_PLUGIN
	end

	if exists(vim.fs.joinpath(dir, ".git")) then
		return PROJ_TYPE.GIT
	end

	return nil
end

---@param dir string
function M.proj_info(dir, cb)
	local type = M.proj_type(dir)
	if type == nil then
		return nil
	end

	local builder = proj_info_builders[type]
	if builder == nil then
		return nil
	end

	return builder(dir, cb)
end

---@param info ProjInfo
function M._update_proj_info_buf(bufnr, info)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local line = 1

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, {})

	NuiLine({ NuiText(info.icon .. ' ' .. info.name, "Title") }):render(bufnr, -1, line)
	line = line + 1
	NuiLine({ NuiText(info.dir, "@comment") }):render(bufnr, -1, line)
	line = line + 1

	for _, line_str in ipairs(info.description) do
		NuiLine({ NuiText(vim.trim(line_str)) }):render(bufnr, -1, line)
		line = line + 1
	end

	if info.unity ~= nil then
	end
end

function M.add_exclude_dir(dir)
	table.insert(exclude_dirs, dir)
end

function M.get_exclude_dirs()
	return exclude_dirs
end

function M.setup(opts)
	vim.api.nvim_create_user_command(
		"ProjInfo",
		function()
			local event = require("nui.utils.autocmd").event
			local popup = NuiPopup({
				enter = true,
				focusable = true,
				border = {
					style = 'rounded',
				},
				position = "50%",
				size = {
					width = "80%",
					height = "60%",
				},
			})
			popup:mount()
			popup:on(event.BufLeave, function()
				popup:unmount()
			end)

			M.proj_info(vim.uv.cwd(), function(info)
				M._update_proj_info_buf(popup.bufnr, info)
			end)
		end,
		{}
	)
end

return M
