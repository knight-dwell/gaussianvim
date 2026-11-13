-- Git helpers shared by the git menu (gitmenu.lua), the Source Control card
-- (scm.lua) and the status line: repository status, stage, commit, push ...
-- Every git command runs in the background; results show as notifications.
local M = {}
local cache = {}            -- repository root → last status

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Git" }) end

-- the repository of the file being edited, else of the current folder
function M.root(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local r = vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" and vim.fs.root(buf, ".git")
  return r or vim.fs.root(vim.uv.cwd(), ".git")
end

-- run `git args` in root; opts.ok: message on success; cb(result) afterwards.
-- No password prompts: a push that would ask for one fails with a message instead of hanging.
function M.run(root, args, opts, cb)
  opts = opts or {}
  vim.system(vim.list_extend({ "git" }, args), {
    cwd = root, text = true,
    env = { GIT_TERMINAL_PROMPT = "0", GIT_SSH_COMMAND = "ssh -o BatchMode=yes" },
  }, vim.schedule_wrap(function(r)
    if r.code == 0 then
      if opts.ok then notify(opts.ok) end
    elseif not opts.quiet then
      local err = vim.trim((r.stderr ~= "" and r.stderr) or r.stdout or "")
      notify(("git %s failed:\n%s"):format(args[1], err), vim.log.levels.ERROR)
    end
    pcall(function() require("gitsigns").refresh() end)
    M.status(root)                          -- refresh menu / card / status line
    if cb then cb(r) end
  end))
end

-- status of root → cb({ branch, upstream, ahead, behind, staged = {}, changes = {} })
-- each file: { path, code }  (code: M modified, A added, D deleted, R renamed, ? new, U conflict)
function M.status(root, cb)
  if not root then return cb and cb(nil) end
  vim.system({ "git", "status", "--porcelain=v1", "-b" }, { cwd = root, text = true }, vim.schedule_wrap(function(r)
    if r.code ~= 0 then return cb and cb(nil) end
    local s = { root = root, branch = "", upstream = false, ahead = 0, behind = 0, staged = {}, changes = {}, time = vim.uv.now() }
    for line in (r.stdout or ""):gmatch("[^\n]+") do
      if line:sub(1, 2) == "##" then
        local b = line:sub(4)
        s.upstream = b:find("%.%.%.") ~= nil
        s.branch = b:match("^No commits yet on (.+)") or b:match("^(.-)%.%.%.") or b:match("^(%S+)") or b
        s.ahead = tonumber(b:match("ahead (%d+)")) or 0
        s.behind = tonumber(b:match("behind (%d+)")) or 0
      else
        local x, y = line:sub(1, 1), line:sub(2, 2)
        local path = line:sub(4):match("-> (.+)$") or line:sub(4)    -- renamed: the new name
        path = path:gsub('^"(.*)"$', "%1")
        if x == "?" then
          s.changes[#s.changes + 1] = { path = path, code = "?" }
        else
          if x ~= " " then s.staged[#s.staged + 1] = { path = path, code = x } end
          if y ~= " " then s.changes[#s.changes + 1] = { path = path, code = y } end
        end
      end
    end
    cache[root] = s
    vim.api.nvim_exec_autocmds("User", { pattern = "GvGitStatus", modeline = false })
    vim.cmd.redrawstatus()
    if cb then cb(s) end
  end))
end

-- last known status of a repository (nil if not read yet)
function M.get(root) return root and cache[root] end

-- last known status of the current repository (refreshed in the background when old)
function M.cached()
  local root = M.root()
  local s = root and cache[root]
  if root and (not s or vim.uv.now() - s.time > 15000) and not M._pending then
    M._pending = true
    M.status(root, function() M._pending = false end)
  end
  return s
end

-- actions -----------------------------------------------------------------

function M.stage(root, path) M.run(root, path and { "add", "--", path } or { "add", "-A" }) end
function M.unstage(root, path) M.run(root, path and { "restore", "--staged", "--", path } or { "reset", "-q" }) end
function M.discard(root, file)
  if file.code == "?" then M.run(root, { "clean", "-f", "--", file.path }, { ok = "Deleted " .. file.path })
  else M.run(root, { "restore", "--", file.path }, { ok = "Discarded changes to " .. file.path }) end
end

function M.commit(root, msg, stage_all, cb)
  local go = function() M.run(root, { "commit", "-m", msg }, { ok = "Committed: " .. msg }, cb) end
  if stage_all then M.run(root, { "add", "-A" }, { quiet = false }, function(r) if r.code == 0 then go() end end) else go() end
end

function M.push(root)
  local s = cache[root]
  M.run(root, (s and not s.upstream) and { "push", "-u", "origin", "HEAD" } or { "push" }, { ok = "Pushed" })
end
function M.pull(root) M.run(root, { "pull", "--ff-only" }, { ok = "Pulled" }) end
function M.fetch(root) M.run(root, { "fetch", "--prune" }, { ok = "Fetched" }) end

-- Sync = pull, then push your commits (as VS Code's "Sync Changes")
function M.sync(root)
  M.run(root, { "pull", "--ff-only" }, {}, function(r)
    if r.code ~= 0 then return end
    local s = cache[root]
    if s and not s.upstream then return M.push(root) end
    M.run(root, { "push" }, { ok = "Synced" })
  end)
end

function M.new_branch(root)
  vim.ui.input({ prompt = "New branch name" }, function(name)
    if name and vim.trim(name) ~= "" then M.run(root, { "switch", "-c", vim.trim(name) }, { ok = "On new branch " .. vim.trim(name) }) end
  end)
end
function M.branches(root) Snacks.picker.git_branches({ cwd = root }) end
function M.history(root) Snacks.picker.git_log({ cwd = root }) end

function M.init(dir)
  vim.system({ "git", "init" }, { cwd = dir, text = true }, vim.schedule_wrap(function(r)
    notify(r.code == 0 and ("New repository in " .. dir) or r.stderr, r.code == 0 and nil or vim.log.levels.ERROR)
  end))
end

-- the editor window files open in (not a menu or card); makes one if needed
function M.edit_window()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == "" and (vim.bo[b].buftype == "" or vim.bo[b].filetype == "snacks_dashboard") then
      return w
    end
  end
  return vim.api.nvim_get_current_win()
end

-- open a changed file; diff = true also shows what changed (staged: against the last commit)
function M.open_file(root, file, diff, staged)
  vim.api.nvim_set_current_win(M.edit_window())
  vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(root, file.path)))
  if diff and file.code ~= "?" then
    vim.defer_fn(function() require("gitsigns").diffthis(staged and "HEAD" or nil) end, 50)
  end
end

-- keep the status line's ↑↓ fresh
vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "DirChanged" }, {
  callback = function() local r = M.root(); if r then M.status(r) end end,
})

return M
