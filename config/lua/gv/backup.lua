-- Backups of LaTeX projects (like Overleaf's history, kept on this computer).
--
--   Space l B        the Backup menu (also the "Backup" button at the top of
--                    the GaussianTeX window, and the right-click menu)
--   Back up now      a .zip of the project (sources, figures, the PDF; no build
--                    files) in ~/GaussianTeX-backups/<project>/
--   Restore…         pick a backup (newest first): unpack it into a new folder
--                    next to the project (safe), or put it back over the project
--                    (the current state is backed up first)
--   Auto backup      on save, at most every N minutes (default: on, 10 min);
--                    the oldest are removed past the "keep" count (default 30)
-- Also: every file keeps its previous version on save (Vim's 'backup') in
-- ~/.local/state/gaussianvim/backup/ (Space l B → "Previous version of this file").
--
-- gv's own config (~/.config/gaussianvim), in the same menu under "gv config":
--   snapshots        a .tar.gz in ~/GaussianTeX-backups/gaussianvim-config/ when gv
--                    starts (at most once a day, the newest 15 kept) or on demand;
--                    restoring one keeps the current config as
--                    ~/.config/gaussianvim.before-restore-<date>
--   history (git)    the config folder is a git repo: saving a config file in gv
--                    commits it, changes made outside gv are committed when gv
--                    starts; "History…" shows each change and can go back to it
local M = {}

M.dir = vim.fn.expand("~/GaussianTeX-backups")
local PROJECTS = vim.fn.expand("~/GaussianTeX")
local CONF = vim.fn.stdpath("data") .. "/gv-backup.json"
local FILE_BACKUPS = vim.fn.stdpath("state") .. "/backup"

local EXCLUDE = { "*.aux", "*.log", "*.synctex.gz", "*.synctex", "*.fdb_latexmk", "*.fls", "*.out", "*.toc",
  "*.lof", "*.lot", "*.blg", "*.bcf", "*.run.xml", "*.xdv", "*.dvi", "*.glo", "*.gls", "*.glg", "*.acn", "*.acr",
  "*.alg", "*.ist", "*.glsdefs", "*.nav", "*.snm", "*.vrb", "*.swp", "*~", ".git/*", "*/.git/*", ".DS_Store",
  ".gvfast/*", "*/.gvfast/*" }

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Backup" }) end

-- settings ---------------------------------------------------------------------
local defaults = { auto = true, every = 10, keep = 30 }
M.conf = vim.deepcopy(defaults)
do
  local f = io.open(CONF, "r")
  if f then
    local ok, t = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(t) == "table" then M.conf = vim.tbl_extend("force", M.conf, t) end
  end
end
local function save_conf()
  vim.fn.mkdir(vim.fs.dirname(CONF), "p")
  local f = io.open(CONF, "w")
  if f then f:write(vim.json.encode(M.conf)); f:close() end
end

-- every saved file keeps its previous version (file.tex~ with the full path in the name)
vim.fn.mkdir(FILE_BACKUPS, "p")
vim.o.backup = true
vim.o.backupdir = FILE_BACKUPS .. "//"

-- which project ----------------------------------------------------------------
-- the project folder of a buffer: vimtex's root, else the top folder under ~/GaussianTeX
function M.project_root(buf)
  buf = buf or 0
  local ok, root = pcall(function() return vim.api.nvim_buf_get_var(buf, "vimtex").root end)
  if ok and type(root) == "string" and root ~= "" then return root end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil end
  name = vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
  local rel = vim.fs.relpath(PROJECTS, name)
  if rel and rel:find("/") then return PROJECTS .. "/" .. rel:match("^[^/]+") end
  return nil
end

local function project_dir_for(root) return M.dir .. "/" .. vim.fs.basename(root) end

-- the backups of a project, newest first: { path, name, time, size }
function M.list(root)
  local dir = project_dir_for(root)
  local out = {}
  if vim.fn.isdirectory(dir) == 0 then return out end
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match("%.zip$") then
      local st = vim.uv.fs_stat(dir .. "/" .. name)
      out[#out + 1] = { path = dir .. "/" .. name, name = name, time = st and st.mtime.sec or 0, size = st and st.size or 0 }
    end
  end
  table.sort(out, function(a, b) return a.time > b.time end)
  return out
end

local function prune(root)
  local list = M.list(root)
  for i = (M.conf.keep or 30) + 1, #list do os.remove(list[i].path) end
end

-- back up -----------------------------------------------------------------------
local last = {}          -- root -> os.time() of the last backup this session
local running = {}

-- quiet: no message on success (auto backups)
function M.now(root, quiet, cb)
  root = root or M.project_root()
  if not root then return notify("Not in a project: open a .tex file first", vim.log.levels.WARN) end
  if running[root] then return end
  if vim.fn.executable("zip") == 0 then return notify("zip isn't installed (sudo apt install zip)", vim.log.levels.WARN) end
  local dir = project_dir_for(root)
  vim.fn.mkdir(dir, "p")
  local out = ("%s/%s-%s.zip"):format(dir, vim.fs.basename(root), os.date("%Y%m%d-%H%M%S"))
  local cmd = { "zip", "-r", "-q", "-y", out, ".", "-x" }
  vim.list_extend(cmd, EXCLUDE)
  running[root] = true
  vim.system(cmd, { cwd = root }, function(r)
    vim.schedule(function()
      running[root] = nil
      if r.code == 0 then
        last[root] = os.time()
        prune(root)
        if not quiet then notify("Backed up to " .. vim.fn.fnamemodify(out, ":~")) end
        if cb then cb(out) end
      else
        notify("Backup failed: " .. vim.trim(r.stderr or ""), vim.log.levels.ERROR)
      end
    end)
  end)
end

-- auto: on save, at most every M.conf.every minutes
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("gv_backup", { clear = true }),
  callback = function(ev)
    if not M.conf.auto then return end
    local root = M.project_root(ev.buf)
    if not root then return end
    -- only real projects (inside ~/GaussianTeX, or a vimtex root with a .tex)
    if not vim.fs.relpath(PROJECTS, root) and vim.bo[ev.buf].filetype ~= "tex" then return end
    if os.time() - (last[root] or 0) < (M.conf.every or 10) * 60 then return end
    if not last[root] then
      -- first save this session: go by the newest backup on disk
      local newest = M.list(root)[1]
      if newest and os.time() - newest.time < (M.conf.every or 10) * 60 then last[root] = newest.time; return end
    end
    M.now(root, true)
  end,
})

-- restore -----------------------------------------------------------------------
local function human_size(n)
  if n > 1e6 then return ("%.1f MB"):format(n / 1e6) end
  return ("%d kB"):format(math.max(1, math.floor(n / 1e3)))
end

local function unzip(zip, dest, cb)
  vim.fn.mkdir(dest, "p")
  vim.system({ "unzip", "-o", "-q", zip, "-d", dest }, {}, function(r)
    vim.schedule(function()
      if r.code ~= 0 then return notify("unzip failed: " .. vim.trim(r.stderr or ""), vim.log.levels.ERROR) end
      cb()
    end)
  end)
end

local function restore_copy(root, b)
  local dest = ("%s-restored-%s"):format(root, os.date("%Y%m%d-%H%M%S", b.time))
  unzip(b.path, dest, function()
    notify("Unpacked into " .. vim.fn.fnamemodify(dest, ":~") .. " (the project itself is untouched)")
    pcall(function() require("gv.texproject").open_dir(dest) end)
  end)
end

local function restore_over(root, b)
  require("gv.menu").confirm("Put this backup back over " .. vim.fs.basename(root) .. "? (it's backed up first)",
    "Restore over the project", function()
      pcall(vim.cmd, "silent! wall")
      M.now(root, true, function(saved)
        unzip(b.path, root, function()
          vim.cmd("checktime")
          notify("Restored " .. b.name .. "\nThe state before is in " .. vim.fn.fnamemodify(saved, ":~"))
        end)
      end)
    end)
end

function M.restore(root)
  root = root or M.project_root()
  if not root then return notify("Not in a project: open a .tex file first", vim.log.levels.WARN) end
  local list = M.list(root)
  if #list == 0 then return notify("No backups of " .. vim.fs.basename(root) .. " yet (Back up now makes one)") end
  local items = {}
  for i, b in ipairs(list) do
    items[#items + 1] = {
      icon = "\u{f0450}", key = i <= 9 and tostring(i) or nil,
      label = ("%s   %s"):format(os.date("%a %d %b %Y  %H:%M", b.time), human_size(b.size)),
      submenu = function()
        return { title = os.date("%d %b %H:%M", b.time), items = {
          { icon = "\u{f0770}", label = "Unpack into a new folder (safe)", key = "n", run = function() restore_copy(root, b) end },
          { icon = "\u{f0450}", label = "Put back over the project…", key = "r", run = function() restore_over(root, b) end },
          { icon = "\u{f0256}", label = "Show the .zip in the file manager", key = "o",
            run = function() vim.system({ "xdg-open", vim.fs.dirname(b.path) }, { detach = true }) end },
        } }
      end,
    }
    if i >= 25 then break end
  end
  require("gv.menu").open({ title = "Restore " .. vim.fs.basename(root), anchor = "center", items = items })
end

-- the previous version of this file (Vim's backup), in a split to compare
function M.previous_version()
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
  if name == "" then return notify("This buffer has no file") end
  local bk = FILE_BACKUPS .. "/" .. name:gsub("/", "%%") .. "~"
  if not vim.uv.fs_stat(bk) then return notify("No previous version yet (it's kept from the next save on)") end
  local ft = vim.bo.filetype
  vim.cmd("diffthis")
  vim.cmd("vert new")
  vim.cmd("silent read " .. vim.fn.fnameescape(bk))
  vim.cmd("1delete _")
  vim.bo.buftype, vim.bo.bufhidden, vim.bo.modifiable, vim.bo.filetype = "nofile", "wipe", false, ft
  pcall(vim.api.nvim_buf_set_name, 0, "previous version: " .. vim.fs.basename(name))
  vim.cmd("diffthis")
  vim.keymap.set("n", "q", "<cmd>diffoff! | close<cr>", { buffer = 0, nowait = true, desc = "Close" })
  notify("Left: the version before your last save (q closes). do / dp move changes.")
end

-- gv's own config -----------------------------------------------------------------
local CONFIG = vim.fn.stdpath("config")
local CFG_DIR = M.dir .. "/gaussianvim-config"
local CFG_KEEP = 15
local GIT_ID = { "-c", "user.name=GaussianVim", "-c", "user.email=gaussianvim@localhost" }

function M.config_list()
  local out = {}
  if vim.fn.isdirectory(CFG_DIR) == 0 then return out end
  for name, kind in vim.fs.dir(CFG_DIR) do
    if kind == "file" and name:match("%.tar%.gz$") then
      local st = vim.uv.fs_stat(CFG_DIR .. "/" .. name)
      out[#out + 1] = { path = CFG_DIR .. "/" .. name, name = name, time = st and st.mtime.sec or 0, size = st and st.size or 0 }
    end
  end
  table.sort(out, function(a, b) return a.time > b.time end)
  return out
end

function M.config_snapshot(quiet, cb)
  vim.fn.mkdir(CFG_DIR, "p")
  local out = ("%s/gaussianvim-config-%s.tar.gz"):format(CFG_DIR, os.date("%Y%m%d-%H%M%S"))
  vim.system({ "tar", "czf", out, "--exclude=__pycache__", "-C", vim.fs.dirname(CONFIG), vim.fs.basename(CONFIG) }, {},
    function(r)
      vim.schedule(function()
        if r.code ~= 0 then return notify("Config backup failed: " .. vim.trim(r.stderr or ""), vim.log.levels.ERROR) end
        local list = M.config_list()
        for i = CFG_KEEP + 1, #list do os.remove(list[i].path) end
        if not quiet then notify("gv config backed up to " .. vim.fn.fnamemodify(out, ":~")) end
        if cb then cb(out) end
      end)
    end)
end

-- git: commit whatever changed in the config (quiet; nothing to commit is fine)
local function git(args, cb)
  local cmd = { "git", "-C", CONFIG }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(r) if cb then vim.schedule(function() cb(r) end) end end)
end

local function git_commit(msg, cb)
  if vim.fn.executable("git") == 0 then return cb and cb() end
  local function commit()
    git({ "add", "-A" }, function()
      local args = vim.list_extend(vim.deepcopy(GIT_ID), { "commit", "-q", "-m", msg })
      git(args, function() if cb then cb() end end)
    end)
  end
  if vim.fn.isdirectory(CONFIG .. "/.git") == 0 then
    git({ "init", "-q", "-b", "main" }, commit)
  else
    commit()
  end
end
M.config_commit = git_commit

-- saving a config file in gv: one commit per save
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("gv_config_git", { clear = true }),
  callback = function(ev)
    local f = vim.fs.normalize(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ev.buf), ":p"))
    local rel = vim.fs.relpath(CONFIG, f)
    if rel then git_commit("Edited " .. rel) end
  end,
})

-- gv starts: changes made outside gv get a commit; a snapshot once a day
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("gv_config_daily", { clear = true }),
  once = true,
  callback = function()
    vim.defer_fn(function()
      git_commit("Changes made outside gv (" .. os.date("%d %b %Y %H:%M") .. ")", function()
        local newest = M.config_list()[1]
        if not newest or os.time() - newest.time > 24 * 3600 then M.config_snapshot(true) end
      end)
    end, 3000)
  end,
})

local function config_restore_snapshot(b)
  require("gv.menu").confirm("Replace gv's config with the backup from " .. os.date("%d %b %H:%M", b.time) .. "?",
    "Restore this config", function()
      M.config_snapshot(true, function()
        local keep = CONFIG .. ".before-restore-" .. os.date("%Y%m%d-%H%M%S")
        local ok, err = os.rename(CONFIG, keep)
        if not ok then return notify("Couldn't move the current config aside: " .. tostring(err), vim.log.levels.ERROR) end
        vim.system({ "tar", "xzf", b.path, "-C", vim.fs.dirname(CONFIG) }, {}, function(r)
          vim.schedule(function()
            if r.code ~= 0 then
              os.rename(keep, CONFIG)       -- put it back as it was
              return notify("Restore failed (nothing changed): " .. vim.trim(r.stderr or ""), vim.log.levels.ERROR)
            end
            notify("Config restored. Restart gv to use it.\nThe config before is in " .. vim.fn.fnamemodify(keep, ":~"))
          end)
        end)
      end)
    end)
end

function M.config_restore()
  local list = M.config_list()
  if #list == 0 then return notify("No config backups yet (Back up gv config now makes one)") end
  local items = {}
  for i, b in ipairs(list) do
    items[#items + 1] = { icon = "\u{f0450}", key = i <= 9 and tostring(i) or nil,
      label = ("%s   %s"):format(os.date("%a %d %b %Y  %H:%M", b.time), human_size(b.size)),
      run = function() config_restore_snapshot(b) end }
  end
  require("gv.menu").open({ title = "Restore gv config", anchor = "center", items = items })
end

-- a commit's changes in a read-only tab (q closes)
local function show_commit(sha)
  git({ "show", "--stat", "--patch", "--format=%h  %ad%n%s%n", "--date=format:%d %b %Y %H:%M", sha }, function(r)
    vim.cmd("tabnew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(r.stdout or "", "\n"))
    vim.bo.buftype, vim.bo.bufhidden, vim.bo.modifiable, vim.bo.filetype = "nofile", "wipe", false, "git"
    vim.keymap.set("n", "q", "<cmd>tabclose<cr>", { buffer = 0, nowait = true, desc = "Close" })
  end)
end

local function go_back_to(sha, when)
  require("gv.menu").confirm("Put gv's config back as it was on " .. when .. "? (this is a new step: it can be undone)",
    "Go back to this version", function()
      git_commit("Before going back to " .. sha, function()
        git({ "restore", "--source=" .. sha, "--staged", "--worktree", ":/" }, function(r)
          if r.code ~= 0 then return notify("git restore failed: " .. vim.trim(r.stderr or ""), vim.log.levels.ERROR) end
          git_commit("Went back to " .. sha .. " (" .. when .. ")", function()
            vim.cmd("checktime")
            notify("Config is back to " .. when .. ". Restart gv to use it.")
          end)
        end)
      end)
    end)
end

function M.config_history()
  if vim.fn.isdirectory(CONFIG .. "/.git") == 0 then return notify("No history yet: it starts with the next change") end
  git({ "log", "-n", "40", "--format=%h%x09%ad%x09%s", "--date=format:%d %b %H:%M" }, function(r)
    local items = {}
    for line in (r.stdout or ""):gmatch("[^\n]+") do
      local sha, when, subj = line:match("^(%S+)\t([^\t]+)\t(.*)$")
      if sha then
        items[#items + 1] = { icon = "\u{f02a2}", label = ("%s  %s"):format(when, subj), submenu = function()
          return { title = sha, items = {
            { icon = "\u{f0208}", label = "Show what changed", key = "s", run = function() show_commit(sha) end },
            { icon = "\u{f0450}", label = "Go back to this version…", key = "r", run = function() go_back_to(sha, when) end },
          } }
        end }
      end
    end
    if #items == 0 then return notify("No history yet") end
    require("gv.menu").open({ title = "gv config history", anchor = "center", items = items })
  end)
end

local function config_submenu()
  local list = M.config_list()
  return { title = "gv config", items = {
    { icon = "\u{f0c7}", label = "Back up gv config now", key = "b",
      run = function() git_commit("Backup " .. os.date("%d %b %H:%M"), function() M.config_snapshot(false) end) end },
    { icon = "\u{f0450}", label = ("Restore a config backup…  (%d)"):format(#list), key = "r", run = M.config_restore },
    { icon = "\u{f02a2}", label = "History of changes (git)…", key = "h", run = M.config_history },
    { icon = "\u{f0256}", label = "Open the config backups folder", key = "o",
      run = function() vim.fn.mkdir(CFG_DIR, "p"); vim.system({ "xdg-open", CFG_DIR }, { detach = true }) end },
  } }
end

-- the menu ----------------------------------------------------------------------
function M.menu(anchor)
  local root = M.project_root()
  local list = root and M.list(root) or {}
  local newest = list[1] and os.date("%d %b %H:%M", list[1].time) or "none yet"
  local function set(k, v) M.conf[k] = v; save_conf() end
  local function choose(title, key, values, fmt)
    return function()
      local items = {}
      for i, v in ipairs(values) do
        items[#items + 1] = { icon = M.conf[key] == v and "\u{f012c}" or " ", label = fmt(v), key = tostring(i),
          run = function() set(key, v); notify(title .. ": " .. fmt(v)) end }
      end
      return { title = title, items = items }
    end
  end
  require("gv.menu").open({
    title = "Backup" .. (root and (": " .. vim.fs.basename(root)) or ""),
    anchor = anchor or "center",
    items = {
      { icon = "\u{f0c7}", label = "Back up now", key = "b", disabled = not root, run = function() M.now(root) end },
      { icon = "\u{f0450}", label = ("Restore…  (%d, newest %s)"):format(#list, newest), key = "r", disabled = not root,
        run = function() M.restore(root) end },
      { icon = "\u{f06a1}", label = "Previous version of this file", key = "p", run = M.previous_version },
      { icon = "\u{f0256}", label = "Open the backups folder", key = "o",
        run = function()
          local d = root and project_dir_for(root) or M.dir
          vim.fn.mkdir(d, "p")
          vim.system({ "xdg-open", d }, { detach = true })
        end },
      { icon = "\u{f0493}", label = "gv config (snapshots, history)", key = "g", submenu = config_submenu },
      "-",
      { icon = M.conf.auto and "\u{f0c8}" or "\u{f0131}", label = "Auto backup on save: " .. (M.conf.auto and "on" or "off"),
        key = "a", run = function() set("auto", not M.conf.auto); notify("Auto backup " .. (M.conf.auto and "on" or "off")) end },
      { icon = "\u{f0954}", label = ("Auto backup at most every %d min"):format(M.conf.every), key = "e",
        submenu = choose("Every", "every", { 2, 5, 10, 15, 30, 60 }, function(v) return v .. " min" end) },
      { icon = "\u{f01b4}", label = ("Keep the newest %d"):format(M.conf.keep), key = "k",
        submenu = choose("Keep", "keep", { 10, 30, 50, 100, 500 }, function(v) return v .. " backups" end) },
    },
  })
end

-- the window's Backup button (runner/gvwindow.py)
_G.GvBackupMenu = function()
  vim.schedule(function() M.menu("center") end)
  return ""
end

vim.keymap.set("n", "<leader>lB", function() M.menu() end, { desc = "Backup: now / restore / settings" })
vim.cmd([[
  amenu PopUp.Backup… <cmd>lua require("gv.backup").menu("cursor")<cr>
]])

return M
