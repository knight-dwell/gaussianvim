-- The colorscheme you last picked (Space sc) is used next time too. The default
-- is "tokyonight", which GaussianVim repaints with the rice palette (plugins/ui.lua).
-- Back to the rice colors: Space sc → tokyonight.
local saved = vim.fn.stdpath("state") .. "/colorscheme"

local f = io.open(saved)
local name = f and f:read("*l")
if f then f:close() end
if name and name ~= vim.g.colors_name and not pcall(vim.cmd.colorscheme, name) then
  vim.cmd.colorscheme("tokyonight")
end

vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function(ev)
    local out = io.open(saved, "w")
    if out then out:write(ev.match, "\n"); out:close() end
  end,
})

require("gv.transparent").apply()
