-- The rendered reader (runner/gvreader.py): Wikipedia / Stack Exchange with the
-- equations typeset and the figures shown, in a WebKit window. gv's text reader
-- can draw maths and pictures only with kitty graphics, so without them (the
-- GaussianTeX / GaussianVim window, gnome-terminal) this window opens by itself;
-- `p` in a text reader opens it any time.
local M = {}
local SCRIPT = vim.fn.stdpath("config") .. "/runner/gvreader.py"

-- true when the terminal can't draw pictures (no kitty graphics)
function M.needed()
  return not (Snacks and Snacks.image and Snacks.image.supports_terminal())
end

-- a desktop, and Python with GTK + WebKit2 (checked once)
function M.available()
  if M._ok == nil then
    M._ok = (vim.env.DISPLAY ~= nil or vim.env.WAYLAND_DISPLAY ~= nil) and vim.fn.filereadable(SCRIPT) == 1
      and vim.system({ "python3", "-c", "import gi\ntry:\n gi.require_version('WebKit2','4.1')\nexcept ValueError:\n gi.require_version('WebKit2','4.0')\nfrom gi.repository import WebKit2" }):wait().code == 0
  end
  return M._ok
end

-- open({ "wiki", title }) / ({ "zim", file, path }) / ({ "html", file, title, base })
function M.open(args)
  if not M.available() then
    return vim.notify("The rendered reader needs a desktop and WebKit2GTK for Python\n(Ubuntu: sudo apt install gir1.2-webkit2-4.1; or run gv-doctor)", vim.log.levels.WARN, { title = "Reader" })
  end
  local cmd = { "python3", SCRIPT }
  vim.list_extend(cmd, args)
  vim.system(cmd, { detach = true, stdout = false, stderr = false })
end

function M.auto(args)
  if M.needed() and M.available() then M.open(args) end
end

return M
