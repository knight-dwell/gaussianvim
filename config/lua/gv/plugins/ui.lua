-- How GaussianVim looks: Material You colors (lua/gv/material.lua), status
-- line, file tabs, start screen, Space menu.

-- A Gaussian drawn with block characters, for the start screen.
local function bell(width, rows)
  local bars = { " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
  local lines, c, sigma = {}, (width - 1) / 2, width / 6
  for r = rows - 1, 0, -1 do
    local line = {}
    for i = 0, width - 1 do
      local h = rows * 8 * math.exp(-((i - c) / sigma) ^ 2 / 2) - r * 8
      line[#line + 1] = bars[math.max(0, math.min(8, math.floor(h + 0.5))) + 1]
    end
    lines[#lines + 1] = table.concat(line)
  end
  return table.concat(lines, "\n")
end

-- hide the file name / type while a GaussianVim menu or card has focus
local function not_menu()
  local ft = vim.bo.filetype
  if ft == "gvrun" or ft == "gvrunterm" or ft == "gvrunpill" or ft == "gvrunplot" or ft == "gvrunview" then return false end
  return not (vim.bo.buftype == "nofile" and ({ gvmenu = true, gvscm = true, gitcommit = true })[ft])
end

-- a LaTeX file: the Compile / PDF buttons show in its window bar
local function is_tex() return vim.bo.filetype == "tex" or vim.bo.filetype == "plaintex" end


-- status line git item, like VS Code's:  main ↑1 ↓2  (click: git menu)
local function git_item()
  local ok, git = pcall(require, "gv.git")
  local s = ok and git.cached() or nil
  local head = vim.b.gitsigns_head or (s and s.branch)
  if not head or head == "" then return "" end
  local out = "\u{e725} " .. head
  if s and s.branch == head then
    if (s.ahead or 0) > 0 then out = out .. " ↑" .. s.ahead end
    if (s.behind or 0) > 0 then out = out .. " ↓" .. s.behind end
  end
  return out
end

return {
  -- Colors: tokyonight's highlight rules, repainted in Material You (lua/gv/material.lua)
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      local material = require("gv.material")
      require("tokyonight").setup({
        style = "night",
        on_colors = material.on_colors,
        on_highlights = material.on_highlights,
      })
      vim.cmd.colorscheme("tokyonight")
    end,
  },

  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- Status line: Material pills
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function()
      local git_menu = function() require("gv.gitmenu").open() end
      return {
        options = {
          theme = require("gv.material").lualine_theme(),
          globalstatus = true,
          component_separators = "",
          section_separators = { left = "\u{e0b4}", right = "\u{e0b6}" },
          disabled_filetypes = {
            statusline = { "snacks_dashboard" },
            winbar = { "snacks_dashboard", "snacks_terminal", "snacks_picker_list", "snacks_layout_box", "gvmenu", "gvscm", "gvrun", "gvrunterm", "gvrunpill", "gvrunplot", "gvrunview",
              "dap-repl", "dapui_scopes", "dapui_breakpoints", "dapui_stacks", "dapui_watches", "dapui_console", "qf", "help" },
          },
        },
        sections = {
          lualine_a = { { "mode", separator = { left = "\u{e0b6}", right = "\u{e0b4}" } } },
          lualine_b = {
            { git_item, on_click = git_menu, separator = { right = "\u{e0b4}" } },   -- click: git menu
          },
          lualine_c = {
            { "diff", on_click = function() require("gv.scm").open() end,          -- click: Source Control
              symbols = { added = "\u{f457} ", modified = "\u{f459} ", removed = "\u{f458} " } },
            { "filename", path = 1, symbols = { modified = " ●", readonly = " \u{f023}" }, cond = not_menu },
            { "diagnostics", symbols = { error = "\u{f057} ", warn = "\u{f071} ", info = "\u{f05a} ", hint = "\u{f0335} " } },
          },
          lualine_x = { { "filetype", cond = not_menu } },
          lualine_y = { { "progress", separator = { left = "\u{e0b6}" } } },
          lualine_z = { { "location", separator = { left = "\u{e0b6}", right = "\u{e0b4}" } } },
        },
        -- breadcrumbs at the top of each window, as in LunarVim: file  class  function
        winbar = {
          lualine_c = {
            { "filename", path = 0, symbols = { modified = " ●", readonly = " \u{f023}" } },
            {
              function() return require("nvim-navic").get_location() end,
              cond = function() return package.loaded["nvim-navic"] and require("nvim-navic").is_available() end,
            },
          },
          -- .tex files: Overleaf's buttons (lua/gv/tex.lua): ▶ Compile (then the
          -- result: ✓ Compiled / ✗ 2 errors, click for the list) and PDF
          lualine_x = {
            {
              function() return " \u{f024b} Files " end,
              cond = is_tex, padding = 0, color = "GvBadge",
              on_click = function() require("gv.tex").files() end,
            },
            { function() return " " end, cond = is_tex, padding = 0 },
            {
              function() return (require("gv.tex").button()) end,
              cond = is_tex, padding = 0,
              color = function() return select(2, require("gv.tex").button()) end,
              on_click = function() require("gv.tex").button_click() end,
            },
            { function() return " " end, cond = is_tex, padding = 0 },
            {
              function() return " \u{f0219} PDF " end,
              cond = is_tex, padding = 0, color = "GvBadge",
              on_click = function() require("gv.tex").view() end,
            },
          },
        },
        inactive_winbar = { lualine_c = { { "filename", path = 0 } } },
      }
    end,
  },

  -- File tabs along the top (Shift+H / Shift+L): Material chips
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    opts = function()
      return {
        options = {
          diagnostics = "nvim_lsp",
          always_show_bufferline = false,
          separator_style = { "", "" },
          indicator = { style = "none" },
          modified_icon = "●",
          show_buffer_close_icons = false,
          offsets = { { filetype = "snacks_layout_box" } },
          close_command = function(n) Snacks.bufdelete(n) end,
        },
        highlights = require("gv.material").bufferline_highlights(),
      }
    end,
  },

  -- Press Space and wait: a menu of what each key does
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      win = { border = "rounded", padding = { 1, 2 }, title = " GaussianVim ", title_pos = "center" },
      spec = {
        { "<leader>a", group = "AI (Claude)" },
        { "<leader>b", group = "Buffers" },
        { "<leader>d", group = "Debug" },
        { "<leader>g", group = "Git" },
        { "<leader>G", desc = "Source control", icon = "\u{f02a2}" },
        { "<leader>l", group = "LSP" },
        { "<leader>p", group = "Plugins" },
        { "<leader>r", group = "Run" },
        { "<leader>s", group = "Search" },
        { "<leader>S", group = "Sessions" },
        { "<leader>T", group = "Treesitter" },
        { "<leader>u", group = "Toggle" },
      },
    },
  },

  -- snacks.nvim: start screen, file finder, file tree, notifications, input boxes
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      dashboard = {
        width = 42,
        preset = {
          header = bell(43, 4) .. "\n\nG A U S S I A N   V I M",
          keys = {
            { icon = "\u{f006f} ", key = "s", desc = "Restore session", action = ":lua require('persistence').load({ last = true })" },
            { icon = "\u{f021e} ", key = "f", desc = "Find file", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = "\u{f0752} ", key = "n", desc = "New file", action = ":ene | startinsert" },
            { icon = "\u{f02da} ", key = "r", desc = "Recent files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = "\u{f13b8} ", key = "g", desc = "Search text", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = "\u{f02a2} ", key = "G", desc = "Source control", action = ":lua require('gv.scm').open()" },
            { icon = "\u{f0219} ", key = "t", desc = "LaTeX projects (GaussianTeX)", action = ":lua require('gv.texproject').start()" },
            { icon = "\u{f02d6} ", key = "?", desc = "Dictionary: every key and alias", action = ":lua vim.system({ vim.fn.expand('~/.local/bin/gv-dict') }, { detach = true })" },
            { icon = "\u{f0493} ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', { cwd = vim.fn.stdpath('config') })" },
            { icon = "\u{f06b0} ", key = "u", desc = "Update plugins", action = ":Lazy sync" },
            { icon = "\u{f05fc} ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        formats = {
          key = function(item) return { { " " .. item.key .. " ", hl = "SnacksDashboardKey" } } end,
        },
        sections = {
          { section = "header", padding = 2 },
          { section = "keys", gap = 1, padding = 2 },
          { section = "startup" },
        },
      },
      picker = { enabled = true, layout = { preset = "default" } },
      explorer = { enabled = true },
      indent = { enabled = false },   -- off, as in your LunarVim (Space ui turns them on)
      notifier = { enabled = true, style = "fancy", top_down = false },
      input = { enabled = true },
      quickfile = { enabled = true },
      bigfile = { enabled = true },
      words = { enabled = true },
      styles = {
        input = { border = "rounded", title_pos = "left", relative = "cursor", row = -3, width = 50 },
        notification = { border = "rounded" },
      },
    },
  },

  -- Git: changed lines in the gutter, blame, stage / undo hunks
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" }, change = { text = "▎" }, delete = { text = "▁" },
        topdelete = { text = "▔" }, changedelete = { text = "▎" }, untracked = { text = "▎" },
      },
    },
  },

  -- Auto-close brackets and quotes
  { "echasnovski/mini.pairs", event = "InsertEnter", opts = {} },
}
