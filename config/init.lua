-- GaussianVim: Neovim set up like LunarVim, with the rice's colors.
-- Started by `gv` (~/.local/bin/gv), which runs Neovim 0.12 from
-- ~/.local/share/gaussianvim with NVIM_APPNAME=gaussianvim, so this config,
-- its plugins and its data never mix with LunarVim (`vim`) or plain `nvim`.
--
--   lua/gv/options.lua    editor settings
--   lua/gv/keymaps.lua    keys (Space is the leader, like LunarVim)
--   lua/gv/lsp.lua        language servers: errors, completion, go-to-definition
--   lua/gv/tex.lua        LaTeX writing: spell check, grammar (Space u g), command menu
--   lua/gv/cheatsheet.lua Space ? : searchable list of Vim commands (cheatsheet.tsv)
--   lua/gv/colors.lua     remembers the colorscheme you pick; transparent.lua: Space ut
--   lua/gv/plugins/*.lua  plugins, installed by lazy.nvim on first start

vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("gv.options")

-- lazy.nvim: the plugin manager (cloned once, on the first start)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = { { import = "gv.plugins" } },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = false },               -- no update checks in the background
  rocks = { enabled = false },                 -- no plugin here needs luarocks
  change_detection = { notify = false },
  ui = { border = "rounded", title = " GaussianVim plugins " },
  performance = {
    rtp = { disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin", "netrwPlugin" } },
  },
})

require("gv.colors")
require("gv.keymaps")
require("gv.lsp")
require("gv.tex")
require("gv.docs")          -- :GvDocs (offline docs)
require("gv.wiki")          -- :GvWiki (Wikipedia)
