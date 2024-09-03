local telescope = require('telescope')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local previewers = require('telescope.previewers')
local utils = require('telescope.utils')
local proj = require('proj')
local Path = require('plenary.path')

local function make_proj_picker_entry(dir)
	local exclude_dirs = proj.get_exclude_dirs()
	for _, exclude_dir in ipairs(exclude_dirs) do
		if vim.startswith(dir, exclude_dir) then
			return nil
		end
	end

	local type = proj.proj_type(dir)
	if type == nil then
		return nil
	end

	local icon = proj.proj_icon(type)
	local dir_path = Path.new(dir)
	return {
		value = dir,
		ordinal = "",
		display = icon .. '  ' .. dir_path:normalize('/'):gsub('\\', '/')
	}
end

local function proj_picker(opts)
	opts = opts or {}
	opts.cwd = opts.cwd and utils.path_expand(opts.cwd) or vim.loop.cwd()
	local finder = finders.new_job(
		function(prompt)
			prompt = prompt or ""
			return { "zoxide", "query", "--list", prompt }
		end,
		make_proj_picker_entry,
		nil,
		opts.cwd
	)

	local previewer = previewers.new_buffer_previewer({
		title = "Project Previewer",
		define_preview = function(self, entry)
			vim.bo[self.state.bufnr].ft = "markdown"
			vim.wo[self.state.winid].wrap = true
			vim.wo[self.state.winid].conceallevel = 3

			proj.proj_info(entry.value, function(info)
				if not vim.api.nvim_buf_is_valid(self.state.bufnr) then
					return
				end

				proj._update_proj_info_buf(self.state.bufnr, info)
			end)
		end,
	})

	local picker = pickers.new(opts, {
		prompt_title = "Projects",
		finder = finder,
		previewer = previewer,
		attach_mappings = function(prompt_bufnr, map)
			map({ "i", "n" }, "<cr>", function(_)
				local entry = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				vim.cmd.cd(entry.value)
				vim.cmd.edit(entry.value)
			end, {})
			return true
		end,
	})
	picker:find()
end

return telescope.register_extension({
	setup = function()

	end,
	exports = {
		proj = proj_picker,
	}
})
