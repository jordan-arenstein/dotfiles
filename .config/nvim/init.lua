-- # plugins
local ensure_packer = function()
	local fn = vim.fn
	local install_path = fn.stdpath("data").."/site/pack/packer/start/packer.nvim"
	if fn.empty(fn.glob(install_path)) > 0 then
		fn.system({"git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", install_path})
		vim.cmd.packadd "packer.nvim"
		return true
	end
	return false
end
local packer_bootstrap = ensure_packer()

require "packer".startup(function (use)
	use "wbthomason/packer.nvim"
	use "tpope/vim-repeat"
	use "tpope/vim-surround"
	use "tpope/vim-commentary"
	use "tpope/vim-rsi"

	use {
		"nvim-treesitter/nvim-treesitter",
		run = function () 
			require "nvim-treesitter.install".update({ with_sync = true }) 
		end,
		config = function ()
			require "nvim-treesitter.configs".setup {
				highlight = {
					enable = true,
					-- disable = { "latex" },
					-- additional_vim_regex_highlighting = { "latex" },
				},
				indent = {
					enable = true,
				},
				playground = {
					enable = true,
				},
			}
		end,
	}
	use "nvim-treesitter/playground"

	use { 
		"folke/which-key.nvim",
		config = function ()
			require "which-key".setup {}
		end
	}

	use {
		"folke/noice.nvim",
		config = function ()
			require "noice".setup {
				presets = {
					-- command_palette = false,
				},
				messages = {
					enabled = true,
					view = "mini",
					view_error = "notify",
					view_warn = "mini",
					view_search = false,
				},
				noitfy = {
					enabled = true,
					view = "notify",
				},

				views = {
					cmdline_popup = {
						border = {
							style = "none",
							padding = { 1, 2 },
						},
						filter_options = {},
						win_options = {
							winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder",
						},
					},
				},
			}
		end,
		requires  = {
			"MunifTanjim/nui.nvim",
			"rcarriga/nvim-notify",
		}
	}

	use {
		"L3MON4D3/LuaSnip",
		config = function () 
			require("luasnip").config.setup {
				update_events = "InsertLeave,TextChanged,TextChangedI",
				delete_check_events = "TextChanged,InsertLeave",
				enable_autosnippets = true,
				ext_opts = {},
			}

			require("luasnip.loaders.from_lua").load("luasnippets")
			vim.keymap.set({ "i", "s" }, "<tab>", function ()
				local luasnip = require "luasnip"
				if luasnip.expand_or_jumpable() then
					luasnip.expand_or_jump()
				end
			end)
			vim.keymap.set({ "i", "s" }, "<s-tab>", function ()
				local luasnip = require "luasnip"
				if luasnip.jumpable(-1) then
					luasnip.jump(-1)
				end
			end)
			vim.keymap.set({ "i", "s" }, "<c-space>", function ()
				local luasnip = require "luasnip"
				if luasnip.choice_active() then
					luasnip.change_choice(1)
				end
			end)
			vim.keymap.set("s", "<bs>", "<bs>a") -- deleting in select mode should enter insert mode at the next snippet point
		end
	}

	use {
		"nvim-telescope/telescope.nvim",
		requires = { "nvim-lua/plenary.nvim" }
	}


	use {
		"folke/twilight.nvim",
		config = function()
			require "twilight".setup {}
		end
	}
	use {
		"folke/zen-mode.nvim",
		config = function()
			require "zen-mode".setup {}
		end
	}

	use {
		"nvim-lualine/lualine.nvim",
		requires = { "kyazdani42/nvim-web-devicons" },
		config = function()
			require "lualine".setup{}
		end,
	}
	use {
		"lervag/vimtex",
		requires = { "wellle/targets.vim" }
	}

	use "altercation/vim-colors-solarized"
	use "savq/melange"
	use "folke/tokyonight.nvim"

	if packer_bootstrap then
		require "packer".sync()
	end
end)

-- use space as the leader key
local leader = " "
vim.keymap.set({"n", "v", "o"}, " ", "<nop>") -- disable space to move the cursor
vim.g.mapleader = leader
vim.g.maplocalleader = leader

-- # system preferences
vim.opt.backup = false
vim.opt.swapfile = false
vim.opt.undofile = true
vim.undodir = vim.fn.stdpath "data" .. "/undo"
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.cmdheight = 1

-- # editing
vim.keymap.set("v", ">", ">gv")
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("n", "<leader>=", "ggvG=") -- indent whole file 
vim.opt.expandtab = false
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.breakindent = true
vim.opt.breakindentopt = "shift:1"
vim.opt.linebreak = true
vim.opt.conceallevel = 0

-- # folds
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

-- # navigation
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
-- searching
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.inccommand = "split"
vim.keymap.set("n", "<leader><leader>", vim.cmd.nohlsearch)
-- telescope
vim.keymap.set("n", "<leader>ff", function () require "telescope.builtin".find_files() end)
vim.keymap.set("n", "<leader>fr", function () require "telescope.builtin".registers() end)
vim.keymap.set("n", "<leader>fg", function () require "telescope.builtin".live_grep() end)
vim.keymap.set("n", "<leader>fb", function () require "telescope.builtin".buffers() end)
vim.keymap.set("n", "<leader>fh", function () require "telescope.builtin".help_tags() end)

-- # aesthetics
vim.opt.termguicolors = true
vim.cmd.colorscheme "tokyonight"
vim.opt.background = "dark"
vim.opt.showtabline = 1

-- # latex
vim.g.tex_flavor = "latex"
vim.g.vimtex_view_method = "skim"
vim.g.vimtex_quickfix_open_on_warning = false
vim.g.vimtex_indent_on_ampersands = false
vim.g.vimtex_indent_delims = {
	open = { "{", "(", "[" },
	close = { "}", ")", "]", },
	close_indented = 0,
	include_modified_math = 1,
}
vim.g.vimtex_complete_enabled = false
vim.g.vimtex_imaps_enabled = false
vim.g.vimtex_indent_enabled = false
vim.g.vimtex_matchparen_enabled = false
vim.g.vimtex_motion_enabled = false
vim.g.vimtex_syntax_conceal_disable = true
vim.g.vimtex_syntax_enabled = false
vim.g.vimtex_text_obj_enabled = true
vim.g.vimtex_toc_enabled = false
vim.opt.wildignore:append { "*.aux", "*.synctex.gz", "*.pdf", "*.fls", "*.fdb_latexmk" }
vim.api.nvim_create_autocmd("User", {
	pattern = "VimtexEventQuit",
	callback = vim.cmd.VimtexClean,
	desc = "clean auxiliary files on quit"
})
