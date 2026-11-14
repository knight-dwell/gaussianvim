-- What LunarVim has built in (debugger, breadcrumbs, sessions) and the plugins
-- from your LunarVim config (~/.config/lvim/config.lua): your colorschemes,
-- vimtex, julia-vim. Apart from vimtex and julia-vim (which must load at start),
-- all of this loads only when used.

-- Your LunarVim colorschemes: loaded only when picked (Space sc)
local colorschemes = {
  "rebelot/kanagawa.nvim", "Shatur/neovim-ayu", "tanvirtin/monokai.nvim", "aditya-azad/candle-grey",
  "neanias/everforest-nvim", "olivercederborg/poimandres.nvim", "elvessousa/sobrio",
  "projekt0n/github-nvim-theme", "ramojus/mellifluous.nvim", "nyoom-engineering/oxocarbon.nvim",
  "yorickpeterse/vim-paper", "n1ghtmare/noirblaze-vim", "kadekillary/skull-vim", "chriskempson/base16-vim",
  "kvrohit/rasmus.nvim", "NLKNguyen/papercolor-theme", "bignimbus/pop-punk.vim", "rose-pine/neovim",
  "oxfist/night-owl.nvim", "cranberry-clockworks/coal.nvim", "nikolvs/vim-sunbather", "widatama/vim-phoenix",
  "ntk148v/komau.vim", "ludvary/photon.vim", "ludvary/sainnhe_gruvbox_brighter", "sainnhe/gruvbox-material",
}

local specs = {
  -- Breadcrumbs: file > class > function at the top of the window (shown by lualine)
  { "SmiteshP/nvim-navic", lazy = true, opts = { highlight = true, separator = " \u{f0142} ", depth_limit = 5 } },

  -- Debugger (LunarVim's Space d): breakpoints, step through, inspect variables
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" }, opts = {} },
      "mfussenegger/nvim-dap-python",
    },
    keys = {
      { "<leader>dt", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
      { "<leader>db", function() require("dap").step_back() end, desc = "Step back" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
      { "<leader>dC", function() require("dap").run_to_cursor() end, desc = "Run to cursor" },
      { "<leader>dd", function() require("dap").disconnect() end, desc = "Disconnect" },
      { "<leader>dg", function() vim.print(require("dap").session()) end, desc = "Get session" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step into" },
      { "<leader>do", function() require("dap").step_over() end, desc = "Step over" },
      { "<leader>du", function() require("dap").step_out() end, desc = "Step out" },
      { "<leader>dp", function() require("dap").pause() end, desc = "Pause" },
      { "<leader>dr", function() require("dap").repl.toggle() end, desc = "Toggle REPL" },
      { "<leader>ds", function() require("dap").continue() end, desc = "Start" },
      { "<leader>dq", function() require("dap").close() end, desc = "Quit" },
      { "<leader>dU", function() require("dapui").toggle({ reset = true }) end, desc = "Toggle UI" },
    },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      -- Python debugging through debugpy (installed by Mason)
      require("dap-python").setup(vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python")
      dap.listeners.after.event_initialized.gv = function() dapui.open() end
      dap.listeners.before.event_terminated.gv = function() dapui.close() end
      dap.listeners.before.event_exited.gv = function() dapui.close() end
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapStopped", { text = "→", texthl = "DiagnosticWarn", linehl = "Visual" })
    end,
  },

  -- Sessions: Space S s restores the files you had open in this folder
  { "folke/persistence.nvim", event = "BufReadPre", opts = {} },

  -- From your LunarVim config: LaTeX (zathura viewer; GaussianTeX builds on this) and Julia
  {
    "lervag/vimtex",
    lazy = false,                     -- vimtex must not be lazy-loaded
    init = function()
      vim.g.vimtex_view_method = "zathura"
      -- the PDF opens by itself after the first compile, once zathura is installed
      vim.g.vimtex_view_automatic = vim.fn.executable("zathura") == 1 and 1 or 0
      -- in the GaussianTeX window (gtex) the PDF opens in its right pane instead (lua/gv/pdfdock.lua)
      if vim.env.GV_DOCK and vim.env.GV_PDF_XID then
        vim.g.vimtex_view_automatic = 0
        vim.g.vimtex_view_zathura_options = "-e " .. vim.env.GV_PDF_XID
          .. " -c " .. vim.fn.stdpath("config") .. "/zathura-dock"
      elseif require("gv.pdfdock").window_available() then
        -- gv in a plain terminal: the PDF button offers to dock it (reopen in the window)
        vim.g.vimtex_view_automatic = 0
      end
      vim.g.vimtex_quickfix_open_on_warning = 0
      vim.g.vimtex_quickfix_mode = 0              -- errors: the Compile button + marks (lua/gv/tex.lua)
      vim.g.vimtex_compiler_silent = 1            -- the button shows the progress
      vim.g.vimtex_quickfix_ignore_filters = { "Underfull", "Overfull" }
      vim.g.vimtex_syntax_nospell_comments = 1   -- spell check the text, not % comments (as Overleaf)
    end,
  },
  { "JuliaEditorSupport/julia-vim", lazy = false },   -- \alpha<Tab> → α in .jl files (must load at start)
}

for _, repo in ipairs(colorschemes) do
  specs[#specs + 1] = { repo, lazy = true }
end
return specs
