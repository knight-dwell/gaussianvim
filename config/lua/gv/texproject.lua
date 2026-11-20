-- GaussianTeX projects (like Overleaf's project list). `gtex` in a terminal, the
-- GaussianTeX app, Space t in gv, or t on the start screen:
--
--   New project      pick a template (thesis, PRB paper, arXiv, Nature letter,
--                    notes, book, slides, blank), give it a name: a folder in
--                    ~/GaussianTeX with everything ready to compile (F5)
--   Open a project   your projects, newest first, with a preview of the main file
--   Import a .zip    a project from Overleaf, arXiv, a colleague: unpacked into
--                    ~/GaussianTeX and opened
--   Rename           a project's folder (open files are saved and reopened)
--   Overleaf         Clone from Overleaf / Sync (Git integration; token in the
--                    GNOME keyring, see ~/.local/bin/gtex-overleaf)
--
-- Templates live in ~/.config/gaussianvim/tex-templates/<name>/ (a template.json
-- and the files); {{TITLE}}, {{AUTHOR}}, {{DATE}} are filled in. Copy a folder
-- there to add your own.
local M = {}
M.root = vim.fn.expand("~/GaussianTeX")
local TEMPLATES = vim.fn.stdpath("config") .. "/tex-templates"

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "GaussianTeX" }) end
local function exists(p) return vim.uv.fs_stat(p) ~= nil end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- the folder name for a project name: letters, digits, - and _ (spaces become -)
local function folder_name(name)
  local s = vim.trim(name):gsub("%s+", "-"):gsub("[^%w%-_%.]", "")
  return s
end

-- the main .tex of a project: main.tex / thesis.tex, else a file with \documentclass
function M.find_main(dir)
  for _, n in ipairs({ "main.tex", "thesis.tex", "paper.tex", "manuscript.tex" }) do
    if exists(dir .. "/" .. n) then return dir .. "/" .. n end
  end
  local found
  for name, kind in vim.fs.dir(dir, { depth = 2 }) do
    if kind == "file" and name:match("%.tex$") then
      local text = read(dir .. "/" .. name) or ""
      if text:match("\\documentclass") then
        if not name:find("/") then return dir .. "/" .. name end   -- top level wins
        found = found or (dir .. "/" .. name)
      end
    end
  end
  return found
end

local function templates()
  local list = {}
  for name, kind in vim.fs.dir(TEMPLATES) do
    if kind == "directory" then
      local ok, meta = pcall(vim.json.decode, read(TEMPLATES .. "/" .. name .. "/template.json") or "")
      if ok and type(meta) == "table" then
        meta.id, meta.dir = name, TEMPLATES .. "/" .. name
        meta.main = meta.main or "main.tex"
        list[#list + 1] = meta
      end
    end
  end
  table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
  return list
end

local function author()
  local r = vim.system({ "git", "config", "user.name" }, { text = true }):wait()
  local name = vim.trim(r.stdout or "")
  return name ~= "" and name or (vim.env.USER or "Author")
end

-- every project: the folders in ~/GaussianTeX, plus .tex projects you opened elsewhere
local function projects()
  local seen, list = {}, {}
  local function add(dir, from_history)
    dir = vim.fs.normalize(dir)
    if seen[dir] or not exists(dir) or (from_history and dir:match("^/tmp/")) then return end
    local main = M.find_main(dir)
    if not main then return end
    seen[dir] = true
    local st = vim.uv.fs_stat(main)
    list[#list + 1] = { dir = dir, main = main, name = vim.fs.basename(dir), mtime = st and st.mtime.sec or 0 }
  end
  if exists(M.root) then
    for name, kind in vim.fs.dir(M.root) do
      if kind == "directory" then add(M.root .. "/" .. name) end
    end
  end
  for _, f in ipairs(vim.v.oldfiles or {}) do
    if f:match("%.tex$") and exists(f) then
      local root = vim.fs.root(f, { "main.tex", "thesis.tex", ".latexmkrc", "latexmkrc" }) or vim.fs.dirname(f)
      add(root, true)
    end
  end
  table.sort(list, function(a, b) return a.mtime > b.mtime end)
  return list
end

-- open a project's main file in the editor window
function M.open_dir(dir)
  local main = M.find_main(vim.fs.normalize(vim.fn.fnamemodify(dir, ":p")))
  if not main then return notify("No .tex file with \\documentclass in " .. dir, vim.log.levels.WARN) end
  local ok, git = pcall(require, "gv.git")
  if ok and git.edit_window then pcall(vim.api.nvim_set_current_win, git.edit_window()) end
  vim.cmd.edit(vim.fn.fnameescape(main))
  vim.cmd.lcd(vim.fn.fnameescape(vim.fs.dirname(main)))
end

-- a picker of projects; on_pick(project)
local function pick_project(title, on_pick)
  local list = projects()
  if #list == 0 then return notify("No projects yet: New project makes one") end
  local items = {}
  for _, p in ipairs(list) do
    items[#items + 1] = {
      text = p.name .. " " .. p.dir, project = p, file = p.main,
      preview = { text = read(p.main) or "", ft = "tex" },
    }
  end
  Snacks.picker.pick({
    title = title, items = items, preview = "preview",
    format = function(item)
      local p = item.project
      return { { "\u{f0219}  " .. p.name, "Title" }, { "   " .. vim.fn.fnamemodify(p.dir, ":~") .. "   " .. os.date("%d %b %Y", p.mtime), "Comment" } }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then vim.schedule(function() on_pick(item.project) end) end
    end,
  })
end

function M.open() pick_project("Open a LaTeX project", function(p) M.open_dir(p.dir) end) end

-- copy a template into a new folder, filling in the title / author / date
local function create(t, name)
  local folder = folder_name(name)
  if folder == "" then return notify("Give the project a name", vim.log.levels.WARN) end
  local dest = M.root .. "/" .. folder
  if exists(dest) then
    notify(("~/GaussianTeX/%s exists already: pick another name"):format(folder), vim.log.levels.WARN)
    return vim.schedule(function() M.ask_name(t, name .. " 2") end)
  end
  vim.fn.mkdir(dest, "p")
  local fill = { TITLE = vim.trim(name), AUTHOR = author(), DATE = os.date("%B %Y") }
  for rel, kind in vim.fs.dir(t.dir, { depth = 10 }) do
    local src, dst = t.dir .. "/" .. rel, dest .. "/" .. rel
    if kind == "directory" then
      vim.fn.mkdir(dst, "p")
    elseif kind == "file" and rel ~= "template.json" then
      vim.fn.mkdir(vim.fs.dirname(dst), "p")
      if rel:match("%.tex$") or rel:match("%.bib$") then
        local text = (read(src) or ""):gsub("{{(%u+)}}", function(k) return fill[k] or ("{{" .. k .. "}}") end)
        local f = assert(io.open(dst, "w"))
        f:write(text)
        f:close()
      else
        vim.uv.fs_copyfile(src, dst)
      end
    end
  end
  M.open_dir(dest)
  notify(("New project: ~/GaussianTeX/%s (%s). F5 compiles it; the Files button shows its files"):format(folder, t.name))
end

M.create = create          -- for scripts: M.create(template, name)

function M.ask_name(t, default)
  Snacks.input({ prompt = "Name of the new project (" .. t.name .. ")", default = default or "" }, function(name)
    if name and vim.trim(name) ~= "" then create(t, name) end
  end)
end

function M.new()
  local list = templates()
  if #list == 0 then return notify("No templates in " .. TEMPLATES, vim.log.levels.ERROR) end
  local items = {}
  for _, t in ipairs(list) do
    items[#items + 1] = {
      text = t.name .. " " .. (t.description or ""), template = t, file = t.dir .. "/" .. t.main,
      preview = { text = read(t.dir .. "/" .. t.main) or "", ft = "tex" },
    }
  end
  Snacks.picker.pick({
    title = "New LaTeX project: choose a template", items = items, preview = "preview",
    layout = { preset = "default" },
    format = function(item)
      return { { "\u{f0219}  " .. item.template.name, "Title" }, { "   " .. (item.template.description or ""), "Comment" } }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then vim.schedule(function() M.ask_name(item.template) end) end
    end,
  })
end

-- a project from a .zip (Overleaf "Download source", arXiv source, ...)
function M.import()
  if vim.fn.executable("zenity") == 0 then return notify("zenity is needed to choose the .zip", vim.log.levels.ERROR) end
  local start = vim.fn.isdirectory(vim.fn.expand("~/Downloads")) == 1 and vim.fn.expand("~/Downloads/") or vim.fn.expand("~/")
  vim.system({ "zenity", "--file-selection", "--title=Import a LaTeX project (.zip)", "--file-filter=Zip files | *.zip",
    "--filename=" .. start }, { text = true }, function(r)
    vim.schedule(function()
      if r.code ~= 0 then return end
      local zip = vim.trim(r.stdout or "")
      local default = vim.fn.fnamemodify(zip, ":t:r")
      Snacks.input({ prompt = "Name of the imported project", default = default }, function(name)
        if not name or vim.trim(name) == "" then return end
        local dest = M.root .. "/" .. folder_name(name)
        if exists(dest) then return notify("~/GaussianTeX/" .. folder_name(name) .. " exists already", vim.log.levels.WARN) end
        vim.fn.mkdir(dest, "p")
        vim.system({ "unzip", "-q", zip, "-d", dest }, {}, function(u)
          vim.schedule(function()
            if u.code ~= 0 then return notify("Couldn't unpack " .. zip, vim.log.levels.ERROR) end
            vim.fn.delete(dest .. "/__MACOSX", "rf")
            -- a zip with one folder inside: use that folder's contents
            local entries = {}
            for n in vim.fs.dir(dest) do entries[#entries + 1] = n end
            if #entries == 1 and vim.fn.isdirectory(dest .. "/" .. entries[1]) == 1 then
              local inner = dest .. "/" .. entries[1]
              for n in vim.fs.dir(inner) do vim.uv.fs_rename(inner .. "/" .. n, dest .. "/" .. n) end
              vim.uv.fs_rmdir(inner)
            end
            M.open_dir(dest)
            notify("Imported into ~/GaussianTeX/" .. folder_name(name))
          end)
        end)
      end)
    end)
  end)
end

-- rename a project's folder; its open files are saved, closed and reopened
local function rename_to(p, name)
  local folder = folder_name(name)
  if folder == "" or folder == p.name then return end
  local dest = vim.fs.dirname(p.dir) .. "/" .. folder
  if exists(dest) then return notify(folder .. " exists already", vim.log.levels.WARN) end
  local was_open = false
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local f = vim.api.nvim_buf_get_name(b)
    if f:sub(1, #p.dir + 1) == p.dir .. "/" then
      was_open = was_open or vim.api.nvim_buf_is_loaded(b)
      vim.api.nvim_buf_call(b, function()
        if vim.b.vimtex and pcall(vim.fn.eval, "b:vimtex.compiler.is_running()") and vim.fn.eval("b:vimtex.compiler.is_running()") == 1 then
          pcall(vim.cmd, "VimtexStop")
        end
        if vim.bo.modified then pcall(vim.cmd, "silent write") end
      end)
      pcall(vim.api.nvim_buf_delete, b, { force = false })
    end
  end
  local ok, err = vim.uv.fs_rename(p.dir, dest)
  if not ok then return notify("Couldn't rename: " .. tostring(err), vim.log.levels.ERROR) end
  notify(("Renamed %s → %s"):format(p.name, folder))
  if was_open then M.open_dir(dest) end
end

function M.rename()
  pick_project("Rename which project?", function(p)
    Snacks.input({ prompt = "New name for " .. p.name, default = p.name }, function(name)
      if name and vim.trim(name) ~= "" then rename_to(p, name) end
    end)
  end)
end

-- ── Overleaf (Git integration) ─────────────────────────────────────────────
-- gtex-overleaf (~/.local/bin) does the work; the token lives in the GNOME keyring.
local OL = vim.fn.expand("~/.local/bin/gtex-overleaf")

local function overleaf(args, on_ok)
  vim.system(vim.list_extend({ OL }, args), { text = true }, function(r)
    vim.schedule(function()
      local out = vim.trim((r.stdout or "") .. "\n" .. (r.stderr or ""))
      if r.code == 0 then on_ok(vim.trim(r.stdout or ""))
      else notify(out ~= "" and out or "Overleaf sync failed", r.code == 2 and vim.log.levels.WARN or vim.log.levels.ERROR) end
    end)
  end)
end

-- make sure a token is stored (asks with a hidden password dialog the first time)
local function with_token(then_do)
  vim.system({ "/usr/bin/python3", "-c",
    "import gi; gi.require_version('Secret','1'); from gi.repository import Secret as S; "
    .. "s=S.Schema.new('io.github.gaussiantex.Overleaf',S.SchemaFlags.NONE,{'service':S.SchemaAttributeType.STRING}); "
    .. "raise SystemExit(0 if S.password_lookup_sync(s,{'service':'overleaf-git'},None) else 1)" }, {}, function(r)
    vim.schedule(function()
      if r.code == 0 then return then_do() end
      notify("Paste your Overleaf Git token (Overleaf → Account settings → Git integration)")
      overleaf({ "token" }, function() then_do() end)
    end)
  end)
end

function M.clone_overleaf()
  Snacks.input({ prompt = "Overleaf project link (or its git link)" }, function(link)
    if not link or vim.trim(link) == "" then return end
    Snacks.input({ prompt = "Name for it in ~/GaussianTeX" }, function(name)
      if not name or vim.trim(name) == "" then return end
      with_token(function()
        notify("Cloning from Overleaf…")
        overleaf({ "clone", link, name }, function(dir)
          M.open_dir(dir)
          notify("Linked to Overleaf: Space t → Sync with Overleaf sends and gets changes")
        end)
      end)
    end)
  end)
end

-- sync the project of the current file (or pick one)
function M.sync_overleaf()
  local file = vim.api.nvim_buf_get_name(0)
  local dir = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  pcall(vim.cmd, "silent! wall")
  with_token(function()
    notify("Syncing with Overleaf…")
    overleaf({ "sync", dir }, function(msg)
      vim.cmd("silent! checktime")          -- reload files co-authors changed
      notify(msg ~= "" and msg or "Synced with Overleaf")
    end)
  end)
end

-- the menu (gtex, Space t, t on the start screen)
function M.start()
  local items = {
    { icon = "\u{f0415}", label = "New project from a template…", key = "n", run = function() vim.schedule(M.new) end },
    { icon = "\u{f0770}", label = "Open a project…", key = "o", run = function() vim.schedule(M.open) end },
    { icon = "\u{f05b3}", label = "Import a .zip (Overleaf, arXiv, …)…", key = "i", run = function() vim.schedule(M.import) end },
    { icon = "\u{f0cb6}", label = "Rename a project…", key = "r", run = function() vim.schedule(M.rename) end },
    { icon = "\u{f0497}", label = "Open a shared project (invitations, shared with you)…", key = "s",
      run = function() vim.schedule(function() require("gv.share").open_shared() end) end },
    "-",
    { icon = "\u{f02a2}", label = "Clone from Overleaf…", key = "c", run = function() vim.schedule(M.clone_overleaf) end },
    { icon = "\u{f04e6}", label = "Sync this project with Overleaf", key = "y", run = function() vim.schedule(M.sync_overleaf) end },
  }
  local recent = projects()
  if #recent > 0 then items[#items + 1] = "-" end
  for i = 1, math.min(5, #recent) do
    local p = recent[i]
    items[#items + 1] = { icon = "\u{f0219}", label = p.name, key = tostring(i), run = function() vim.schedule(function() M.open_dir(p.dir) end) end }
  end
  require("gv.menu").open({ title = "GaussianTeX projects", anchor = "center", items = items })
end

M.templates = templates
M.projects = projects
M.rename_to = rename_to

return M
