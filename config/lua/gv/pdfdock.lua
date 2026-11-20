-- The PDF pane on the right of the GaussianTeX window (runner/gvwindow.py,
-- started by `gtex`): zathura lives inside the window instead of popping up as
-- its own window, and folds away / comes back.
--
--   PDF button      (top right of a .tex file, Space l v) show this spot in the PDF
--   bottom bar      " PDF ▸" / " PDF ◂": click to fold the pane / bring it back
--   Space l h       fold / show the PDF pane (also Ctrl+Shift+P, the "hide"
--                   button above the PDF, the "PDF" tab at the right edge)
--   Ctrl+click      in the PDF: jump to that line in gv
-- Outside the GaussianTeX window (gv in a plain terminal) the PDF opens in
-- zathura as its own window, as before.
local M = {}

local SOCK, XID = vim.env.GV_DOCK, vim.env.GV_PDF_XID
M.state = "empty"           -- "shown" | "hidden" | "empty" (no PDF in the pane)

function M.active() return SOCK ~= nil and SOCK ~= "" and XID ~= nil and XID ~= "" end

local WINDOW = vim.fn.stdpath("config") .. "/runner/gvwindow.py"
local GV = vim.fn.expand("~/.local/bin/gv")

-- could the GaussianTeX window run here? (X11 desktop, GTK + VTE for Python)
local win_ok
function M.window_available()
  if M.active() then return false end
  if win_ok ~= nil then return win_ok end
  win_ok = false
  if (vim.env.DISPLAY or "") ~= "" and (vim.env.XDG_SESSION_TYPE or "x11") == "x11"
      and vim.uv.fs_stat(WINDOW) and vim.fn.executable("python3") == 1 then
    local r = vim.system({ "python3", "-c",
      'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("Vte", "2.91")' }):wait(3000)
    win_ok = r.code == 0
  end
  return win_ok
end

-- gv in a plain terminal -> the GaussianTeX window: everything is saved, the
-- session (open files, splits, cursor) goes along, this gv quits.
function M.move_to_window()
  if vim.fn.executable("setsid") == 0 then return end
  local ok = pcall(vim.cmd, "wall")
  if not ok then
    return vim.notify("Save or close the files that can't be saved first", vim.log.levels.WARN, { title = "PDF" })
  end
  local sess = vim.fn.stdpath("state") .. "/gv-move-session.vim"
  local so = vim.o.sessionoptions
  vim.o.sessionoptions = "buffers,curdir,folds,tabpages,winsize"
  -- floats, trees and terminals don't survive a session; close them first
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then pcall(vim.api.nvim_win_close, w, true) end
  end
  vim.cmd("mksession! " .. vim.fn.fnameescape(sess))
  vim.o.sessionoptions = so
  -- the new window starts once this gv has quit (no "swap file exists")
  local sh = ("while kill -0 %d 2>/dev/null; do sleep 0.1; done; cd %s && exec python3 %s %s -S %s")
    :format(vim.fn.getpid(), vim.fn.shellescape(vim.fn.getcwd()), vim.fn.shellescape(WINDOW),
      vim.fn.shellescape(GV), vim.fn.shellescape(sess))
  vim.system({ "setsid", "-f", "sh", "-c", sh }, { detach = true, env = { GV_DOCK = "", GV_PDF_XID = "" } })
  vim.cmd("confirm qa")
end

-- the PDF button in a plain terminal: dock it, or zathura on its own
function M.ask_plain(open_plain)
  if vim.g.gv_pdf_plain then return open_plain() end
  require("gv.menu").open({
    title = "Where should the PDF go?", anchor = "center",
    items = {
      { icon = "\u{f0219}", label = "Docked on the right, like Overleaf (reopens gv in the GaussianTeX window)",
        key = "d", run = M.move_to_window },
      { icon = "\u{f05b7}", label = "In its own zathura window", key = "w", run = open_plain },
      { icon = "\u{f05b7}", label = "Own window, and don't ask again this session", key = "a",
        run = function() vim.g.gv_pdf_plain = true; open_plain() end },
    },
  })
end

local function refresh() pcall(function() require("lualine").refresh({ place = { "statusline" } }) end) end

-- one command to the window; cb(state)
local function send(cmd, cb)
  if not M.active() then return end
  local pipe = vim.uv.new_pipe(false)
  pipe:connect(SOCK, function(err)
    if err then pipe:close(); return end
    pipe:write(cmd .. "\n")
    local got = ""
    pipe:read_start(function(e, data)
      if data then got = got .. data end
      if e or not data or got:find("\n") then
        pipe:read_stop()
        if not pipe:is_closing() then pipe:close() end
        local st = vim.trim(got)
        vim.schedule(function()
          if st ~= "" then M.state = st end
          refresh()
          if cb then cb(M.state) end
        end)
      end
    end)
  end)
end
M.send = send

-- zathura in the pane -------------------------------------------------------------
local Z = { job = nil, pdf = nil, alive = false }

local function alive() return Z.alive end

function M.open(pdf, line, col, file)
  local fwd = (line and file) and { "--synctex-forward", ("%d:%d:%s"):format(line, col or 1, file) } or {}
  if alive() and Z.pdf == pdf then
    if #fwd > 0 then
      local cmd = { "zathura", "--synctex-pid", tostring(Z.job.pid) }
      vim.list_extend(cmd, fwd)
      cmd[#cmd + 1] = pdf
      vim.system(cmd, { detach = true })
    end
    return send("show")
  end
  if alive() then pcall(function() Z.job:kill(15) end) end
  -- Ctrl+click in the PDF: back to the line in gv (vimtex's inverse search)
  local inverse = vim.v.progpath .. [[ --headless -c "VimtexInverseSearch %{line}:%{column} '%{input}'"]]
  local cmd = { "zathura", "-e", XID, "-c", vim.fn.stdpath("config") .. "/zathura-dock", "-x", inverse }
  -- no --synctex-forward on the first start: if another window's zathura shows the same
  -- PDF, zathura hands the jump to THAT one and quits, and this pane stays empty
  cmd[#cmd + 1] = pdf
  local me = {}
  local ok, job = pcall(vim.system, cmd, { text = true }, function()
    me.dead = true
    vim.schedule(function()
      if Z.me == me then Z.alive = false end
      send("state")
    end)
  end)
  if not ok then
    return vim.notify("zathura didn't start: " .. tostring(job), vim.log.levels.WARN, { title = "PDF" })
  end
  Z.job, Z.pdf, Z.alive, Z.me = job, pdf, true, me
  send("pid " .. job.pid)
  -- the pane opens by itself when zathura has embedded; keep the keyboard in gv
  vim.defer_fn(function() send("focus-term") end, 900)
  -- then jump to the cursor's spot, in OUR viewer (by its pid)
  if #fwd > 0 then
    vim.defer_fn(function()
      if Z.me ~= me or not Z.alive then return end
      local c = { "zathura", "--synctex-pid", tostring(job.pid) }
      vim.list_extend(c, fwd)
      c[#c + 1] = pdf
      vim.system(c, { detach = true })
    end, 1200)
  end
end

local function pdf_path()
  local ok, p = pcall(vim.fn.eval, "b:vimtex.compiler.get_file('pdf')")
  return ok and type(p) == "string" and p or ""
end

-- this spot of the .tex file in the PDF (the PDF button / Space l v)
function M.view()
  local pdf = pdf_path()
  if pdf == "" or vim.fn.filereadable(pdf) == 0 then return false end
  local cur = vim.api.nvim_win_get_cursor(0)
  M.open(vim.fn.fnamemodify(pdf, ":p"), cur[1], cur[2] + 1, vim.api.nvim_buf_get_name(0))
  return true
end

-- fold away / bring back
function M.toggle()
  if not M.active() then return require("gv.tex").view() end
  if not alive() or M.state == "empty" then
    if vim.b.vimtex == nil then
      return vim.notify("Open the .tex file first: the PDF comes from it", vim.log.levels.INFO, { title = "PDF" })
    end
    return require("gv.tex").view()
  end
  send("toggle")
end

function M.status()
  if M.state == "shown" then return " \u{f0219} PDF \u{25b8} " end
  if M.state == "hidden" then return " \u{f0219} PDF \u{25c2} " end
  return " \u{f0219} PDF "
end

if M.active() then
  local grp = vim.api.nvim_create_augroup("gv_pdfdock", { clear = true })
  -- the PDF opens in the pane after the first successful compile (as zathura did before)
  local opened_once = false
  vim.api.nvim_create_autocmd("User", {
    pattern = "VimtexEventCompileSuccess", group = grp,
    callback = function()
      if alive() or opened_once then return end
      vim.defer_fn(function()
        if not alive() and M.view() then opened_once = true end
      end, 100)
    end,
  })
  -- opening a project: show its PDF right away when it has been compiled before
  vim.api.nvim_create_autocmd("User", {
    pattern = "VimtexEventInitPost", group = grp,
    callback = function()
      vim.defer_fn(function()
        if not alive() and vim.b.vimtex ~= nil then M.view() end
      end, 250)
    end,
  })
  -- Ctrl+click in the PDF jumped here: the keyboard comes back to gv
  vim.api.nvim_create_autocmd("User", {
    pattern = "VimtexEventViewReverse", group = grp,
    callback = function() send("focus-term") end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = grp,
    callback = function() if alive() then pcall(function() Z.job:kill(15) end) end end,
  })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tex", "plaintex" }, group = grp,
    callback = function(ev)
      vim.keymap.set("n", "<leader>lh", M.toggle, { buffer = ev.buf, desc = "PDF pane: fold away / show" })
    end,
  })
  -- closing the window asks gv to quit, like :qa (asks about unsaved files)
  -- (✕ or Super+Q). Robust: leave insert / terminal mode and close menus / pickers
  -- first; with nothing unsaved, quit even if a terminal job (AI chat, shell) runs;
  -- with unsaved files, ask Save / Discard / Cancel; never fail silently.
  local function unsaved()
    local list = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified
          and (vim.bo[b].buftype == "" or vim.bo[b].buftype == "acwrite") then
        local n = vim.api.nvim_buf_get_name(b)
        list[#list + 1] = n ~= "" and vim.fn.fnamemodify(n, ":~:.") or "[No Name]"
      end
    end
    return list
  end
  _G.GvWindowClose = function()
    vim.schedule(function()
      local m = vim.fn.mode()
      if m:sub(1, 1) == "t" then
        vim.api.nvim_feedkeys(vim.keycode("<C-\\><C-n>"), "n", false)
      elseif m ~= "n" then
        pcall(vim.cmd, "stopinsert")
        if m:match("^[vVs\22]") then vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false) end
      end
      -- after the mode change has happened
      vim.schedule(function()
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative ~= "" then
            pcall(vim.api.nvim_win_close, w, true)
          end
        end
        local left = unsaved()
        if #left == 0 then
          vim.cmd("silent! wall")                  -- nothing to lose; ends terminal jobs too
          vim.cmd("qa!")
          return
        end
        send("focus-term")                         -- bring the question into view
        local ok, err = pcall(vim.cmd, "confirm qa")
        if not ok and not tostring(err):match("E5108") then
          vim.notify("Couldn't close: " .. tostring(err):gsub("^.-:%d+: ", "")
            .. "\nUnsaved: " .. table.concat(left, ", "), vim.log.levels.WARN, { title = "GaussianTeX" })
        end
      end)
    end)
    return ""
  end
  -- the window tells gv when the pane changed from its side (hide button, tab, Ctrl+Shift+P)
  _G.GvPdfState = function(st)
    vim.schedule(function() M.state = st; refresh() end)
    return ""
  end
  -- the window's toolbar buttons (runner/gvwindow.py)
  _G.GvWinAction = function(what)
    vim.schedule(function()
      if what == "compile" then
        local ok, tex = pcall(require, "gv.tex")
        if vim.b.vimtex == nil then
          return vim.notify("Open the .tex file first", vim.log.levels.INFO, { title = "Compile" })
        end
        if ok then tex.compile() end
      elseif what == "pdf" then
        M.toggle()
      elseif what == "files" then
        Snacks.explorer()
      elseif what == "find" then
        Snacks.picker.files()
      elseif what == "copy" then
        local m = vim.fn.mode()
        if m == "v" or m == "V" or m == "\22" then
          vim.api.nvim_feedkeys('"+y', "nx", false)
          vim.notify("Copied", vim.log.levels.INFO, { title = "Copy" })
        else
          vim.notify("Select text first (drag with the mouse, or v and move), then Copy.\n"
            .. "Or Shift+drag to select anything on screen.", vim.log.levels.INFO, { title = "Copy" })
        end
      end
    end)
    return ""
  end
  vim.schedule(function() send(("server %s %s"):format(vim.v.servername, vim.v.progpath)) end)
end

return M
