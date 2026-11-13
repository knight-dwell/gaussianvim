-- Writing code: syntax highlighting, completion, formatting, language servers.

-- Languages with tree-sitter highlighting (parsers are compiled once, on first start).
-- LaTeX is left to vimtex (GaussianTeX), whose highlighting understands TeX better.
local languages = {
  "python", "lua", "vim", "vimdoc", "query", "bash", "c", "cpp", "fortran", "julia",
  "markdown", "markdown_inline", "json", "yaml", "toml", "make", "cmake",
  "bibtex", "regex", "diff", "gitcommit", "html", "css", "javascript",
  "latex",   -- only to typeset $maths$ in Markdown (Snacks.image); .tex files keep vimtex's highlighting
}
local NO_TS = { tex = true, plaintex = true }   -- vimtex: its syntax drives spell check and the maths aliases

return {
  -- Syntax highlighting + smarter indentation (tree-sitter)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install(languages)
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          if NO_TS[vim.bo[ev.buf].filetype] then return end
          if pcall(vim.treesitter.start, ev.buf) then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- Completion menu while you type, with the function's signature and docs
  --   Tab / Shift+Tab or Ctrl+J / Ctrl+K: move through the list   Enter: accept
  --   Ctrl+Space: open it   Ctrl+E: close it   Ctrl+D / Ctrl+F: scroll the docs
  --   gs (normal mode): the signature of the function under the cursor
  {
    "saghen/blink.cmp",
    version = "1.*",                -- a release with a prebuilt (fast) matcher
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = {
        preset = "enter",
        -- inside an alias / snippet Tab always jumps to the next blank (Ctrl+j / Ctrl+k
        -- still move through the menu); otherwise Tab moves through the menu
        ["<Tab>"] = { "snippet_forward", "select_next", "fallback" },
        ["<S-Tab>"] = { "snippet_backward", "select_prev", "fallback" },
        ["<C-j>"] = { "select_next", "fallback" },              -- as in LunarVim
        ["<C-k>"] = { "select_prev", "fallback" },
        ["<C-d>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },
      },
      completion = {
        list = { selection = { preselect = false, auto_insert = true } },  -- Enter on nothing = newline
        documentation = { auto_show = true, auto_show_delay_ms = 250 },
        menu = { draw = { treesitter = { "lsp" } } },
      },
      signature = { enabled = true },   -- argument hints while typing f(a, b, ...)
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        providers = {
          snippets = {
            opts = {
              -- LaTeX uses GaussianTeX's own short aliases (snippets/tex.json:
              -- frac, intgrl, pdv, matrix, figure, table, ...), not friendly-snippets' set
              filter_snippets = function(ft, file)
                return not ((ft == "tex" or ft == "plaintex") and file:match("friendly%-snippets") ~= nil)
              end,
            },
          },
        },
      },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
  },

  -- Formatting: Space l f (Python with ruff; other languages via their language server)
  {
    "stevearc/conform.nvim",
    cmd = "ConformInfo",
    keys = {
      { "<leader>lf", function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
        mode = { "n", "v" }, desc = "Format file / selection" },
    },
    opts = {
      formatters_by_ft = { python = { "ruff_organize_imports", "ruff_format" } },
    },
  },

  -- Mason installs language servers into ~/.local/share/gaussianvim/mason (no sudo).
  -- :Mason shows them; add more there with i.
  { "mason-org/mason.nvim", opts = { ui = { border = "rounded" } } },
  {
    "mason-org/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      -- Python (types + errors), Python (fast lint), C/C++, Bash, Lua, Fortran,
      -- LaTeX (texlab: completion), grammar (ltex_plus: LanguageTool)
      ensure_installed = { "basedpyright", "ruff", "clangd", "bashls", "lua_ls", "fortls", "texlab", "ltex_plus" },
      -- LanguageTool is switched on / off by lua/gv/tex.lua (Space u g)
      automatic_enable = { exclude = { "ltex_plus" } },
    },
  },
}
