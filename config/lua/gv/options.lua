-- Editor settings. `:help 'name'` explains any of them.
local o = vim.opt

o.number = true            -- line numbers
o.relativenumber = false
o.cursorline = false       -- no line highlight (as in your LunarVim)
o.signcolumn = "yes"       -- room for error / git marks, so text doesn't jump
o.mouse = "a"              -- the mouse works: click, scroll, drag splits
o.clipboard = "unnamedplus" -- y / p use the system clipboard
o.undofile = true          -- undo history survives closing the file
o.confirm = true           -- ask to save instead of refusing to quit

o.expandtab = true         -- Tab inserts spaces
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true

o.ignorecase = true        -- search ignores case ...
o.smartcase = true         -- ... unless you type a capital letter
o.splitright = true        -- new splits open right / below
o.splitbelow = true
o.scrolloff = 8            -- keep 8 lines visible above/below the cursor
o.sidescrolloff = 8
o.wrap = true              -- wrap long lines (as in your LunarVim)
o.linebreak = true         -- ... at word boundaries

o.termguicolors = true
o.showmode = false         -- the status line already shows the mode
o.laststatus = 3           -- one status line for the whole window
o.pumheight = 12           -- completion menu height
o.updatetime = 250         -- faster hover / diagnostics refresh
o.timeoutlen = 400         -- how long Space waits before showing the key menu
o.fillchars = { eob = " " } -- no ~ on empty lines
o.winborder = "rounded"    -- rounded borders on every popup (Neovim 0.11+)
o.title = true
o.titlestring = "GaussianVim · %t"

-- Briefly highlight what you yank
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank({ timeout = 180 }) end,
})

-- Reopen a file at the line you left it
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 1 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
