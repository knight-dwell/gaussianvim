-- Switch GaussianVim's look from inside gv: Space u T, or :GvTheme [material|classic]
--   material  Material title bar, rounded editor / file tree, rendered Wikipedia reader
--   classic   the look before that (kitty launchers, old toolbar)
-- Both are git branches of this config; ~/.local/bin/gv-theme checks one out and sets
-- the app launchers to match. gv then restarts itself (in the GaussianTeX / GaussianVim
-- window) on the same file; in a terminal, start gv again.
local M = {}
local SCRIPT = vim.fn.expand("~/.local/bin/gv-theme")
local CFG = vim.fn.stdpath("config")

M.themes = {
  { id = "material", icon = "\u{f0e09}", label = "Material — title bar, rounded cards, rendered reader" },
  { id = "classic", icon = "\u{f0e0a}", label = "Classic — the look before the Material update" },
}

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Theme" }) end

function M.current()
  local r = vim.system({ "git", "-C", CFG, "branch", "--show-current" }, { text = true }):wait()
  return vim.trim(r.stdout or "")
end

-- start gv again on the same file, in a new window like this one, then quit this one
local function restart()
  local file = vim.api.nvim_buf_get_name(0)
  local cmd
  if vim.env.GV_DOCK then
    if file:match("%.tex$") then
      cmd = { vim.fn.expand("~/.local/bin/gtex"), file }
    else
      cmd = { "gtk-launch", "gaussianvim" }
      if file ~= "" and vim.uv.fs_stat(file) then cmd[#cmd + 1] = file end
    end
  end
  if not cmd then
    return notify("Switched. Quit gv (:qa) and start it again to see the new look.")
  end
  vim.cmd("silent! wall")
  vim.system(cmd, { detach = true, cwd = vim.fn.getcwd(), env = { GV_DOCK = "", GV_NO_ROUTE = "" } })
  vim.defer_fn(function() vim.cmd("qa") end, 300)
end

function M.switch(id)
  if vim.fn.executable(SCRIPT) == 0 then return notify("~/.local/bin/gv-theme is missing", vim.log.levels.ERROR) end
  if id == M.current() then return notify("Already using " .. id) end
  vim.cmd("silent! wall")
  vim.system({ SCRIPT, id }, { text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then
        return notify("Couldn't switch:\n" .. vim.trim((r.stderr or "") .. (r.stdout or "")), vim.log.levels.ERROR)
      end
      vim.ui.select({ "Restart gv now", "Later" }, { prompt = "Switched to " .. id .. ". Restart now?" }, function(c)
        if c == "Restart gv now" then restart() else notify("Switched to " .. id .. ". It applies when gv starts again.") end
      end)
    end)
  end)
end

function M.pick()
  local cur = M.current()
  local items = {}
  for i, t in ipairs(M.themes) do
    items[#items + 1] = { icon = t.icon, label = t.label .. (t.id == cur and "  (active)" or ""), key = tostring(i),
      run = function() vim.schedule(function() M.switch(t.id) end) end }
  end
  require("gv.menu").open({ title = "GaussianVim look", anchor = "center", items = items })
end

vim.api.nvim_create_user_command("GvTheme", function(o)
  if o.args == "" then M.pick() else M.switch(o.args) end
end, { nargs = "?", complete = function() return { "material", "classic" } end,
  desc = "GaussianVim look: material or classic" })

return M
