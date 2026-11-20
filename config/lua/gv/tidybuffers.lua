-- Tidy file tabs: when a real file is opened, empty unnamed ("[No Name]") buffers and
-- leftover directory buffers disappear from the tab bar. Never touches a buffer that
-- has text in it, has unsaved changes, or is still shown in a window.
local function is_junk(b)
  if not (vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted) then return false end
  if vim.bo[b].modified or vim.bo[b].buftype ~= "" then return false end
  local name = vim.api.nvim_buf_get_name(b)
  if name ~= "" and vim.fn.isdirectory(name) == 0 then return false end
  if vim.api.nvim_buf_line_count(b) > 1 or (vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or "") ~= "" then return false end
  return #vim.fn.win_findbuf(b) == 0
end

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("gv_tidybuffers", { clear = true }),
  callback = function(ev)
    local name = vim.api.nvim_buf_get_name(ev.buf)
    if vim.bo[ev.buf].buftype ~= "" or name == "" or vim.fn.isdirectory(name) == 1 then return end
    vim.schedule(function()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if b ~= ev.buf and is_junk(b) then pcall(vim.api.nvim_buf_delete, b, {}) end
      end
    end)
  end,
})
