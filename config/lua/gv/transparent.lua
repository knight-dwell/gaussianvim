-- Space ut: transparent background (kitty's blurred wallpaper shows through),
-- like Make_transp() in your LunarVim config. Remembered across restarts and
-- reapplied when you change colorscheme.
local M = {}
local flag = vim.fn.stdpath("state") .. "/transparent"
local groups = { "Normal", "NormalNC", "NormalFloat", "FloatBorder", "SignColumn", "EndOfBuffer",
  "LineNr", "FoldColumn", "WinBar", "WinBarNC", "SnacksDashboardNormal" }

function M.on() return vim.uv.fs_stat(flag) ~= nil end

function M.apply()
  if not M.on() then return end
  for _, g in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
    hl.bg = nil
    vim.api.nvim_set_hl(0, g, hl)
  end
end

function M.toggle()
  if M.on() then
    os.remove(flag)
    vim.cmd.colorscheme(vim.g.colors_name)   -- reload: brings the background back
  else
    io.open(flag, "w"):close()
    M.apply()
  end
end

vim.api.nvim_create_autocmd("ColorScheme", { callback = M.apply })
return M
