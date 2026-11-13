-- Language servers: errors and warnings on each line, completion, go to definition.
-- The servers themselves are installed by mason (lua/gv/plugins/coding.lua).

-- How errors look: a mark in the gutter, a short message at the end of the line,
-- the full message in a popup (Space l d, or hover the line and wait).
vim.diagnostic.config({
  severity_sort = true,
  update_in_insert = false,           -- don't flash errors while you're still typing
  virtual_text = { spacing = 2, prefix = "●" },
  float = { border = "rounded", source = true },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "\u{f057} ",
      [vim.diagnostic.severity.WARN] = "\u{f071} ",
      [vim.diagnostic.severity.INFO] = "\u{f05a} ",
      [vim.diagnostic.severity.HINT] = "\u{f0335} ",
    },
  },
})

-- Every server learns what the completion menu can show
local ok, blink = pcall(require, "blink.cmp")
if ok then
  vim.lsp.config("*", { capabilities = blink.get_lsp_capabilities() })
end

-- Python: basedpyright for types/completion, ruff for lint. "standard" checking
-- reports real mistakes without nagging about every missing type annotation.
vim.lsp.config("basedpyright", {
  settings = {
    basedpyright = {
      analysis = { typeCheckingMode = "standard", diagnosticMode = "openFilesOnly" },
    },
  },
})
vim.lsp.config("ruff", {
  on_attach = function(client) client.server_capabilities.hoverProvider = false end,  -- pyright's hover is better
})
vim.lsp.config("lua_ls", {
  settings = { Lua = { diagnostics = { globals = { "vim", "Snacks" } }, telemetry = { enable = false } } },
})

-- LaTeX: texlab fills the completion menu with \commands, environments,
-- \ref labels and \cite keys (chktex style nagging off)
vim.lsp.config("texlab", {
  settings = {
    texlab = {
      chktex = { onOpenAndSave = false, onEdit = false },
      diagnostics = { ignoredPatterns = { "^Unused label" } },   -- noise while drafting
    },
  },
})

-- Grammar for LaTeX (LanguageTool, ltex_plus): set up in lua/gv/tex.lua

-- Keys that only exist in a file with a language server (LunarVim's layout)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local function map(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc }) end
    map("gd", function() Snacks.picker.lsp_definitions() end, "Go to definition")
    map("gD", vim.lsp.buf.declaration, "Go to declaration")
    map("gr", function() Snacks.picker.lsp_references() end, "Where is this used")
    map("gI", function() Snacks.picker.lsp_implementations() end, "Go to implementation")
    map("gs", vim.lsp.buf.signature_help, "Function signature")
    map("gl", function() vim.diagnostic.open_float({ scope = "line" }) end, "Show this line's error")
    map("K", vim.lsp.buf.hover, "Docs for the word under the cursor")
    map("<leader>la", vim.lsp.buf.code_action, "Code action / quick fix")
    map("<leader>ld", function() Snacks.picker.diagnostics_buffer() end, "Errors in this file")
    map("<leader>lw", function() Snacks.picker.diagnostics() end, "Errors in all open files")
    map("<leader>li", "<cmd>checkhealth vim.lsp<cr>", "Info")
    map("<leader>lI", "<cmd>Mason<cr>", "Mason (install servers)")
    map("<leader>lj", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next error")
    map("<leader>lk", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Previous error")
    map("<leader>ll", vim.lsp.codelens.run, "CodeLens action")
    map("<leader>lq", vim.diagnostic.setloclist, "Errors to the location list")
    map("<leader>lr", vim.lsp.buf.rename, "Rename everywhere")
    map("<leader>ls", function() Snacks.picker.lsp_symbols() end, "Functions / classes in this file")
    map("<leader>lS", function() Snacks.picker.lsp_workspace_symbols() end, "Symbols in the project")
    map("<leader>le", function() Snacks.picker.qflist() end, "Quickfix list")

    -- breadcrumbs at the top of the window (file > class > function), like LunarVim
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/documentSymbol") then
      local ok, navic = pcall(require, "nvim-navic")
      if ok and not vim.b[ev.buf].navic_client_id then navic.attach(client, ev.buf) end
    end
  end,
})
