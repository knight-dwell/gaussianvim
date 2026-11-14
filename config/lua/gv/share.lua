-- Share a LaTeX project with other GaussianVim users, like Overleaf's "Share",
-- through a PRIVATE GitHub repository (only the people you invite can see it).
--
--   Share button (title bar), Space l o, or `gtex` → Open a shared project:
--
--   Share on GitHub…     the project becomes a private repo on your GitHub
--                        account (build files like .aux / .log / the PDF stay out)
--   Invite someone…      by GitHub username or email; GitHub emails them an invitation
--   Sync                 save, take your collaborators' changes, send yours
--                        (both of you changed the same lines → a card to pick)
--   People with access   who can edit; remove someone or cancel an invitation
--   Open a shared project…   on the other computer: invitations (accept in one
--                        click), projects shared with you, your own shared projects
--
-- Works over plain HTTPS / SSH to github.com (no special ports). Needs the GitHub
-- CLI `gh`, logged in once (the menu offers it). Opening a project in a shared
-- folder checks in the background whether someone else changed it.
local menu = require("gv.menu")
local M = {}

local PROJECTS = vim.fn.expand("~/GaussianTeX")
local TOPIC = "gaussiantex"                  -- marks repos shared from gv (found again on another computer)
local MAX_MB, WARN_MB = 100, 50              -- GitHub refuses files over 100 MB, warns over 50 MB

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Share" }) end
local function exists(p) return vim.uv.fs_stat(p) ~= nil end

-- run a command in the background; cb(result) on the main loop. No password prompts.
local function run(cmd, cwd, cb)
  vim.system(cmd, {
    cwd = cwd, text = true,
    env = { GIT_TERMINAL_PROMPT = "0", GH_PROMPT_DISABLED = "1", GIT_SSH_COMMAND = "ssh -o BatchMode=yes" },
  }, vim.schedule_wrap(function(r) if cb then cb(r) end end))
end
local function git(root, args, cb) run(vim.list_extend({ "git" }, args), root, cb) end
local function err_of(r) return vim.trim((r.stderr ~= "" and r.stderr) or r.stdout or "") end

-- ── the project ────────────────────────────────────────────────────────────

-- the project folder of the current file (vimtex's root, else the folder under ~/GaussianTeX)
function M.root()
  local ok, backup = pcall(require, "gv.backup")
  local r = ok and backup.project_root() or nil
  if r then return vim.fs.normalize(r) end
end

-- the project's OWN repository only: never a repository further up (your home
-- folder may be one), so nothing outside the project is ever uploaded
local function own_repo(root) return root and exists(root .. "/.git") end

-- owner/name from a github.com remote URL
local function slug_of(url)
  url = vim.trim(url or "")
  local s = url:match("github%.com[:/](.-)%.git$") or url:match("github%.com[:/](.-)/?$")
  return s ~= "" and s or nil
end

-- the GitHub repository this project syncs with (owner/name), and the raw origin URL
function M.remote_now(root)
  if not own_repo(root) then return nil end
  local r = vim.system({ "git", "remote", "get-url", "origin" }, { cwd = root, text = true }):wait(3000)
  if r.code ~= 0 then return nil end
  return slug_of(r.stdout), vim.trim(r.stdout)
end
function M.remote(root, cb) cb(M.remote_now(root)) end

-- cb(branch): the branch being worked on (main for projects shared from gv)
local function branch(root, cb)
  git(root, { "branch", "--show-current" }, function(r)
    local b = vim.trim(r.stdout or "")
    cb(b ~= "" and b or "main")
  end)
end

-- ── GitHub login ───────────────────────────────────────────────────────────

local me                                     -- { login, name, id } once known

-- cb(user) when gh is installed and logged in; otherwise offers the login
local function with_github(cb)
  if vim.fn.executable("gh") == 0 then
    return menu.open({ title = "Sharing needs the GitHub CLI (gh)", anchor = "center", items = {
      { icon = "\u{f02fc}", label = "Install it: sudo apt install gh  (Fedora: dnf, Arch: github-cli)", disabled = true },
      { icon = "\u{f0156}", label = "Close", key = "q" },
    } })
  end
  if me then return cb(me) end
  run({ "gh", "api", "user", "--jq", "[.login, (.name // \"\"), .id] | @tsv" }, nil, function(r)
    if r.code == 0 then
      local login, name, id = r.stdout:match("^([^\t]*)\t([^\t]*)\t([^\t\n]*)")
      me = { login = login, name = (name ~= "" and name or login), id = id }
      return cb(me)
    end
    menu.open({ title = "Log in to GitHub to share projects", anchor = "center", items = {
      { icon = "\u{f02a4}", label = "Log in (opens your browser once)", key = "l", run = function() M.login(function() with_github(cb) end) end },
      { icon = "\u{f0156}", label = "Not now", key = "q" },
    } })
  end)
end

-- `gh auth login` in a floating terminal; then git uses the same login (gh auth setup-git)
function M.login(after)
  local sh = "gh auth login -h github.com --web --git-protocol https && gh auth setup-git && " ..
    "printf '\\n  Logged in. This closes in a moment.\\n' && sleep 2"
  local term = Snacks.terminal.open({ "sh", "-c", sh }, { win = { position = "float", border = "rounded", width = 0.7, height = 0.5,
    title = " GitHub login " }, auto_close = true, interactive = true })
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = term.buf, once = true,
    callback = function() me = nil; vim.defer_fn(function() if after then after() end end, 300) end,
  })
end

-- commits need a name: use the GitHub one when git has none (only inside this project)
local function ensure_identity(root, user, cb)
  git(root, { "config", "user.name" }, function(r)
    if r.code == 0 and vim.trim(r.stdout) ~= "" then return cb() end
    git(root, { "config", "user.name", user.name }, function()
      git(root, { "config", "user.email", ("%s+%s@users.noreply.github.com"):format(user.id, user.login) }, function() cb() end)
    end)
  end)
end

-- ── what each person's compile makes: never shared ─────────────────────────

local IGNORE = {
  "# written by GaussianVim (Share): files every compile makes; each person compiles their own PDF",
  "*.aux", "*.log", "*.out", "*.toc", "*.lof", "*.lot", "*.fls", "*.fdb_latexmk", "*.synctex.gz",
  "*.synctex(busy)", "*.bbl", "*.blg", "*.bcf", "*.run.xml", "*.acn", "*.acr", "*.alg", "*.glo", "*.gls",
  "*.glg", "*.ist", "*.idx", "*.ilg", "*.ind", "*.nav", "*.snm", "*.vrb", "*.xdv", "*.dvi", "*.listing",
  ".gvfast/", ".teamtype/", "*.swp", "*~",
}

local function write_ignore(root)
  local path = root .. "/.gitignore"
  local have, lines = {}, {}
  local f = io.open(path, "r")
  if f then for l in f:lines() do have[l] = true end f:close() end
  for _, l in ipairs(IGNORE) do if not have[l] then lines[#lines + 1] = l end end
  -- the PDF of the main file (figures can be PDFs too: those stay shared)
  local main = require("gv.texproject").find_main(root)
  if main then
    local pdf = "/" .. vim.fs.relpath(root, main):gsub("%.tex$", ".pdf")
    if not have[pdf] then lines[#lines + 1] = pdf end
  end
  if #lines == 0 then return end
  f = io.open(path, "a")
  if not f then return end
  if next(have) then f:write("\n") end
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
end

-- ── Share: the project → a private GitHub repo ─────────────────────────────

local function repo_name(root)
  local n = vim.fs.basename(root):gsub("[^%w%-_.]", "-")
  return n
end

-- files about to be uploaded: cb(count, total_bytes, big = { {path, mb} }, too_big = { ... })
-- Reads the folder without changing it (a scratch git directory when it has none yet).
local function upload_summary(root, cb)
  local tmp = vim.fn.tempname()
  vim.fn.writefile(IGNORE, tmp .. ".ignore")
  local main = require("gv.texproject").find_main(root)
  local excl = { "--exclude-from=" .. tmp .. ".ignore" }
  if main then excl[#excl + 1] = "--exclude=/" .. vim.fs.relpath(root, main):gsub("%.tex$", ".pdf") end
  local pre = own_repo(root) and {} or { "--git-dir=" .. tmp .. ".git", "--work-tree=" .. root }
  if not own_repo(root) then vim.system({ "git", "init", "-q", "--bare", tmp .. ".git" }):wait(5000) end
  local args = vim.list_extend(pre, { "ls-files", "-z", "--cached", "--others", "--exclude-standard" })
  git(root, vim.list_extend(args, excl), function(r)
    vim.fn.delete(tmp .. ".git", "rf"); vim.fn.delete(tmp .. ".ignore")
    local n, total, big, too_big = 0, 0, {}, {}
    for p in (r.stdout or ""):gmatch("[^%z]+") do
      local st = vim.uv.fs_stat(root .. "/" .. p)
      if st then
        n, total = n + 1, total + st.size
        local mb = st.size / 1048576
        if mb > MAX_MB then too_big[#too_big + 1] = { p, mb } elseif mb > WARN_MB then big[#big + 1] = { p, mb } end
      end
    end
    cb(n, total, big, too_big)
  end)
end

function M.share(root)
  root = root or M.root()
  if not root then return notify("Open a file of the LaTeX project first", vim.log.levels.WARN) end
  with_github(function(user)
    M.remote(root, function(slug)
      if slug then return M.invite(root, slug) end
      local _, url = M.remote_now(root)
      if url then return notify("This project already syncs with " .. url .. " (not GitHub)", vim.log.levels.WARN) end
      pcall(vim.cmd, "silent! wall")
      upload_summary(root, function(n, total, big, too_big)
        M._confirm_share(root, user, { n = n, total = total, big = big, too_big = too_big })
      end)
    end)
  end)
end

function M._confirm_share(root, user, s, name)
  name = name or repo_name(root)
  local items = {
    { icon = "\u{f0214}", label = ("%d files, %.1f MB will be uploaded"):format(s.n, s.total / 1048576), disabled = true },
    { icon = "\u{f0214}", label = "Left out: .aux .log .bbl …, the compiled PDF (everyone compiles their own)", disabled = true },
  }
  for _, b in ipairs(s.too_big) do
    items[#items + 1] = { icon = "\u{f0026}", icon_hl = "GvDeleted", label = ("%s is %.0f MB: GitHub takes at most 100 MB per file"):format(b[1], b[2]), disabled = true }
  end
  for _, b in ipairs(s.big) do
    items[#items + 1] = { icon = "\u{f0026}", label = ("%s is %.0f MB (large: uploads slowly)"):format(b[1], b[2]), disabled = true }
  end
  items[#items + 1] = "-"
  if #s.too_big == 0 then
    items[#items + 1] = { icon = "\u{f02a4}", label = ("Share privately as %s/%s"):format(user.login, name), key = "s",
      run = function() M._create(root, user, name, s.total) end }
    items[#items + 1] = { icon = "\u{f0cb6}", label = "Another name on GitHub…", key = "n", run = function()
      vim.ui.input({ prompt = "Name of the repository on GitHub", default = name }, function(v)
        v = v and vim.trim(v):gsub("[^%w%-_.]", "-")
        if v and v ~= "" then M._confirm_share(root, user, s, v) end
      end)
    end }
  else
    items[#items + 1] = { icon = "\u{f0214}", label = "Make those files smaller (or add them to .gitignore), then Share again", disabled = true }
  end
  items[#items + 1] = { icon = "\u{f0156}", label = "Cancel", key = "q" }
  menu.open({ title = "Share " .. vim.fs.basename(root) .. " (private)", anchor = "center", items = items })
end

function M._create(root, user, name, bytes)
  local function start(cb)
    if own_repo(root) then return cb() end
    git(root, { "init", "-q", "-b", "main" }, function(r)
      if r.code ~= 0 then return notify("git init failed:\n" .. err_of(r), vim.log.levels.ERROR) end
      cb()
    end)
  end
  start(function()
  write_ignore(root)
  ensure_identity(root, user, function()
    git(root, { "add", "-A" }, function(r)
      if r.code ~= 0 then return notify("git add failed:\n" .. err_of(r), vim.log.levels.ERROR) end
      git(root, { "commit", "-q", "-m", "Shared from GaussianTeX" }, function()   -- (nothing new: fine)
        git(root, { "branch", "-M", "main" }, function()
          notify(("Uploading %s (%.0f MB)… this can take a while; keep working"):format(name, bytes / 1048576))
          run({ "gh", "repo", "create", name, "--private", "--source", root, "--remote", "origin", "--push",
                "--description", "LaTeX project shared from GaussianTeX" }, root, function(c)
            if c.code ~= 0 then
              local e = err_of(c)
              if e:find("already exists") then
                return notify(("You already have a GitHub repository called %s.\nShare again and choose “Another name”."):format(name), vim.log.levels.WARN)
              end
              return notify("Sharing failed:\n" .. e, vim.log.levels.ERROR)
            end
            local slug = user.login .. "/" .. name
            run({ "gh", "repo", "edit", slug, "--add-topic", TOPIC }, root)
            notify("Shared privately: github.com/" .. slug .. "\nNow invite the people who should edit it.")
            vim.defer_fn(function() M.invite(root, slug) end, 400)
          end)
        end)
      end)
    end)
  end)
  end)
end

-- ── invitations and people ─────────────────────────────────────────────────

local function invite_text(root, slug)
  return ("I shared the LaTeX project “%s” with you (private, on GitHub).\n" ..
    "1. Accept the invitation GitHub emailed you (or: https://github.com/%s/invitations)\n" ..
    "2. In GaussianVim: gtex → Open a shared project (or Space t, then s).\n" ..
    "   Without gv: git clone https://github.com/%s.git\n" ..
    "To get each other's changes: the Share button → Sync (Space l o s)."):format(vim.fs.basename(root), slug, slug)
end

local function add_person(root, slug, login)
  run({ "gh", "api", "-X", "PUT", ("repos/%s/collaborators/%s"):format(slug, login), "-f", "permission=push" }, nil, function(r)
    if r.code ~= 0 then
      local e = err_of(r)
      if e:find("Not Found") then return notify("No GitHub user called “" .. login .. "”", vim.log.levels.WARN) end
      return notify("Invitation failed:\n" .. e, vim.log.levels.ERROR)
    end
    vim.fn.setreg("+", invite_text(root, slug))
    notify(("Invited %s: GitHub emails them now.\nA short how-to-open message is copied: paste it in a mail or chat."):format(login))
  end)
end

function M.invite(root, slug)
  vim.ui.input({ prompt = "Invite: their GitHub username or email" }, function(who)
    who = who and vim.trim(who)
    if not who or who == "" then return end
    if not who:find("@") then return add_person(root, slug, who:gsub("^@", "")) end
    -- an email: the GitHub account that shows it
    run({ "gh", "api", "-X", "GET", "search/users", "-f", "q=" .. who .. " in:email", "--jq", ".items[].login" }, nil, function(r)
      local logins = vim.split(vim.trim(r.stdout or ""), "\n", { trimempty = true })
      if r.code == 0 and #logins == 1 then return add_person(root, slug, logins[1]) end
      menu.open({ title = "No GitHub account shows " .. who .. " publicly", anchor = "center", items = {
        { icon = "\u{f0014}", label = "Ask them for their GitHub username, invite that…", key = "u", run = function() M.invite(root, slug) end },
        { icon = "\u{f01ee}", label = "Invite by email on github.com (opens the browser)", key = "b", run = function()
          vim.fn.setreg("+", who)
          vim.ui.open(("https://github.com/%s/settings/access"):format(slug))
          notify("On the page: “Add people”, paste the email (copied). They need a free GitHub account.")
        end },
        { icon = "\u{f0156}", label = "Cancel", key = "q" },
      } })
    end)
  end)
end

function M.people(root, slug)
  run({ "gh", "api", ("repos/%s/collaborators"):format(slug), "--jq", ".[] | [.login, .role_name] | @tsv" }, nil, function(c)
    run({ "gh", "api", ("repos/%s/invitations"):format(slug), "--jq", ".[] | [.id, .invitee.login] | @tsv" }, nil, function(i)
      local items = {}
      for line in (c.stdout or ""):gmatch("[^\n]+") do
        local login, role = line:match("^([^\t]+)\t?(.*)")
        local mine = me and login == me.login
        items[#items + 1] = { icon = "\u{f0004}", label = login .. (mine and "  (you, owner)" or ("  (" .. (role ~= "" and role or "edit") .. ")")),
          disabled = mine, submenu = not mine and function() return { title = login, items = {
            { icon = "\u{f0015}", icon_hl = "GvDeleted", label = "Remove " .. login .. " (no more access)", key = "r", run = function()
              run({ "gh", "api", "-X", "DELETE", ("repos/%s/collaborators/%s"):format(slug, login) }, nil, function(r)
                notify(r.code == 0 and (login .. " removed") or ("Failed:\n" .. err_of(r)), r.code == 0 and nil or vim.log.levels.ERROR)
              end)
            end } } } end or nil }
      end
      for line in (i.stdout or ""):gmatch("[^\n]+") do
        local id, login = line:match("^(%d+)\t(.+)")
        if id then
          items[#items + 1] = { icon = "\u{f01ee}", label = login .. "  (invited, not accepted yet)", submenu = function() return { title = login, items = {
            { icon = "\u{f0156}", icon_hl = "GvDeleted", label = "Cancel the invitation", key = "c", run = function()
              run({ "gh", "api", "-X", "DELETE", ("repos/%s/invitations/%s"):format(slug, id) }, nil, function(r)
                notify(r.code == 0 and ("Invitation to " .. login .. " cancelled") or ("Failed:\n" .. err_of(r)))
              end)
            end } } } end }
        end
      end
      if c.code ~= 0 then items[#items + 1] = { icon = "\u{f0026}", label = "Couldn't read the list: " .. err_of(c):sub(1, 60), disabled = true } end
      items[#items + 1] = "-"
      items[#items + 1] = { icon = "\u{f0014}", label = "Invite someone…", key = "i", run = function() M.invite(root, slug) end }
      menu.open({ title = "People with access to " .. slug, anchor = "center", items = items })
    end)
  end)
end

-- ── Sync ───────────────────────────────────────────────────────────────────

local function conflicted(root, cb)
  git(root, { "diff", "--name-only", "--diff-filter=U" }, function(r)
    cb(vim.split(vim.trim(r.stdout or ""), "\n", { trimempty = true }))
  end)
end

local function has_markers(path)
  local f = io.open(path, "r")
  if not f then return false end
  local s = f:read("*a")
  f:close()
  return s:find("\n<<<<<<< ", 1, true) ~= nil or s:sub(1, 8) == "<<<<<<< "
end

local function open_at_marker(path)
  pcall(vim.api.nvim_set_current_win, require("gv.git").edit_window())
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.fn.search("^<<<<<<< ", "cw")
end

-- readable markers: "<<<<<<< yours" / ">>>>>>> theirs (name)" instead of HEAD / a hash
local function relabel(root, files, cb)
  git(root, { "log", "-1", "--format=%an", "MERGE_HEAD" }, function(r)
    local who = vim.trim(r.stdout or "")
    for _, f in ipairs(files) do
      local path = root .. "/" .. f
      local fh = io.open(path, "r")
      if fh then
        local s = fh:read("*a")
        fh:close()
        local t = s:gsub("\n<<<<<<< HEAD\n", "\n<<<<<<< yours\n"):gsub("^<<<<<<< HEAD\n", "<<<<<<< yours\n")
          :gsub("\n>>>>>>> %x+\n", "\n>>>>>>> theirs" .. (who ~= "" and (" (" .. who .. ")") or "") .. "\n")
        if t ~= s then fh = io.open(path, "w"); if fh then fh:write(t); fh:close() end end
      end
    end
    cb()
  end)
end

-- both of you changed the same lines: pick, or edit the marked spots by hand
function M._conflicts(root, files, labelled)
  if not labelled then return relabel(root, files, function() M._conflicts(root, files, true) end) end
  vim.cmd("silent! checktime")
  local items = {
    { icon = "\u{f0026}", label = "Between <<<<<<< and ======= is yours, then theirs until >>>>>>>", disabled = true },
    { icon = "\u{f0026}", label = "Keep what's right, delete the marker lines, save, then Sync again", disabled = true },
    "-",
  }
  for _, f in ipairs(files) do
    local path = root .. "/" .. f
    items[#items + 1] = { icon = "\u{f0214}", icon_hl = "GvDeleted", label = f, submenu = function() return { title = f, items = {
      { icon = "\u{f03cc}", label = "Open at the first marked spot", key = "o", run = function() open_at_marker(path) end },
      { icon = "\u{f0004}", label = "Keep my version of the whole file", key = "m", run = function()
        git(root, { "checkout", "--ours", "--", f }, function() git(root, { "add", "--", f }, function() vim.cmd("silent! checktime"); notify("Kept yours: " .. f) end) end)
      end },
      { icon = "\u{f000e}", label = "Take their version of the whole file", key = "t", run = function()
        git(root, { "checkout", "--theirs", "--", f }, function() git(root, { "add", "--", f }, function() vim.cmd("silent! checktime"); notify("Took theirs: " .. f) end) end)
      end },
    } } end }
  end
  items[#items + 1] = "-"
  items[#items + 1] = { icon = "\u{f04e6}", label = "Done: Sync again", key = "s", run = function() M.sync(root) end }
  menu.open({ title = "You both changed the same lines", anchor = "center", items = items })
  if files[1] then open_at_marker(root .. "/" .. files[1]) end
end

local function push(root, done_msg)
  git(root, { "push", "-q", "-u", "origin", "HEAD" }, function(p)
    if p.code ~= 0 then return notify("Couldn't send your changes:\n" .. err_of(p), vim.log.levels.ERROR) end
    M._behind[root] = 0
    notify(done_msg)
  end)
end

-- after a pull: who changed what (old..new), reload the open files
local function report(root, old, cb)
  git(root, { "rev-parse", "HEAD" }, function(h)
    local new = vim.trim(h.stdout or "")
    if old == "" or old == new then return cb("Synced ✓  (nothing new from the others)") end
    vim.cmd("silent! checktime")
    git(root, { "log", "--no-merges", "--format=%an", old .. ".." .. new }, function(a)
      git(root, { "diff", "--name-only", old, new }, function(d)
        local who, seen = {}, {}
        for n in (a.stdout or ""):gmatch("[^\n]+") do if not seen[n] then seen[n] = true; who[#who + 1] = n end end
        local files = vim.split(vim.trim(d.stdout or ""), "\n", { trimempty = true })
        local shown = table.concat(vim.list_slice(files, 1, 6), ", ") .. (#files > 6 and (" + " .. (#files - 6) .. " more") or "")
        cb(("Synced ✓  From %s: %s"):format(#who > 0 and table.concat(who, ", ") or "the others", shown))
      end)
    end)
  end)
end

function M.sync(root)
  root = root or M.root()
  if not root then return notify("Open a file of the LaTeX project first", vim.log.levels.WARN) end
  M.remote(root, function(slug)
    if not slug then return M.menu() end
    pcall(vim.cmd, "silent! wall")
    conflicted(root, function(files)
      -- finishing a sync that stopped at a conflict
      if #files > 0 then
        local left = vim.tbl_filter(function(f) return has_markers(root .. "/" .. f) end, files)
        if #left > 0 then return M._conflicts(root, left) end
        return git(root, { "add", "-A" }, function()
          git(root, { "commit", "-q", "--no-edit" }, function(c)
            if c.code ~= 0 then return notify("Couldn't finish:\n" .. err_of(c), vim.log.levels.ERROR) end
            push(root, "Synced ✓  (both versions put together)")
          end)
        end)
      end
      with_github(function(user)
        ensure_identity(root, user, function()
          git(root, { "add", "-A" }, function()
            git(root, { "diff", "--cached", "--quiet" }, function(d)
              local function pull()
                git(root, { "rev-parse", "HEAD" }, function(h)
                  local old = vim.trim(h.stdout or "")
                  notify("Syncing " .. vim.fs.basename(root) .. "…")
                  branch(root, function(b)
                  git(root, { "pull", "-q", "--no-rebase", "--no-edit", "origin", b }, function(p)
                    if p.code ~= 0 then
                      return conflicted(root, function(cf)
                        if #cf > 0 then return M._conflicts(root, cf) end
                        notify("Couldn't get the others' changes:\n" .. err_of(p), vim.log.levels.ERROR)
                      end)
                    end
                    report(root, old, function(msg) push(root, msg) end)
                  end)
                  end)
                end)
              end
              if d.code == 0 then return pull() end          -- nothing of yours to send
              local msg = ("%s: edits from %s"):format(user.name, vim.uv.os_gethostname())
              git(root, { "commit", "-q", "-m", msg }, function(c)
                if c.code ~= 0 then return notify("Couldn't save a version:\n" .. err_of(c), vim.log.levels.ERROR) end
                pull()
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- ── background check: did someone else change it? ──────────────────────────

M._behind, M._checked = {}, {}
function M.check(root, quiet_if_none)
  if not own_repo(root) or (M._checked[root] and vim.uv.now() - M._checked[root] < 300000) then return end
  if exists(root .. "/.git/MERGE_HEAD") then return end      -- in the middle of a Sync with a conflict
  M._checked[root] = vim.uv.now()
  M.remote(root, function(slug)
    if not slug then return end
    git(root, { "fetch", "-q", "origin" }, function(f)
      if f.code ~= 0 then return end
      git(root, { "log", "--no-merges", "--format=%an", "HEAD..@{u}" }, function(l)
        local who, seen, n = {}, {}, 0
        for a in (l.stdout or ""):gmatch("[^\n]+") do
          n = n + 1
          if not seen[a] then seen[a] = true; who[#who + 1] = a end
        end
        M._behind[root] = n
        if n > 0 then
          notify(("%s changed %s (%d new version%s).\nSync to get them: the Share button, or Space l o s"):format(
            table.concat(who, ", "), vim.fs.basename(root), n, n == 1 and "" or "s"))
        elseif not quiet_if_none then
          notify("Nothing new from the others")
        end
      end)
    end)
  end)
end

vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("gv_share_check", { clear = true }),
  pattern = { "*.tex", "*.bib" },
  callback = function(ev)
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(ev.buf) then return end
      local ok, root = pcall(function()
        return vim.api.nvim_buf_call(ev.buf, function() return M.root() end)
      end)
      if ok and root then M.check(root, true) end
    end, 1500)
  end,
})

-- ── on the other computer: open a project shared with you ──────────────────

local function local_dir_for(name)
  local d = PROJECTS .. "/" .. name
  local i = 2
  while exists(d) do d = ("%s/%s-%d"):format(PROJECTS, name, i); i = i + 1 end
  return d
end

-- a project already on this computer that syncs with slug
local function find_local(slug)
  for name, t in vim.fs.dir(PROJECTS) do
    local d = PROJECTS .. "/" .. name
    if t == "directory" and exists(d .. "/.git") then
      local r = vim.system({ "git", "remote", "get-url", "origin" }, { cwd = d, text = true }):wait(2000)
      if r.code == 0 and slug_of(r.stdout) == slug then return d end
    end
  end
end

function M.clone(slug)
  local here = find_local(slug)
  if here then return require("gv.texproject").open_dir(here) end
  with_github(function(user)
    vim.fn.mkdir(PROJECTS, "p")
    local dest = local_dir_for(slug:match("[^/]+$"))
    notify("Downloading " .. slug .. "…")
    run({ "gh", "repo", "clone", slug, dest, "--", "-q" }, PROJECTS, function(r)
      if r.code ~= 0 then return notify("Download failed:\n" .. err_of(r), vim.log.levels.ERROR) end
      ensure_identity(dest, user, function()
        notify(("%s is in %s\nSync (Share button, Space l o s) gets the others' changes and sends yours."):format(slug, dest))
        require("gv.texproject").open_dir(dest)
      end)
    end)
  end)
end

function M.open_shared()
  with_github(function(user)
    notify("Looking for projects shared with you…")
    run({ "gh", "api", "user/repository_invitations", "--jq", ".[] | [.id, .repository.full_name, .inviter.login] | @tsv" }, nil, function(inv)
      run({ "gh", "api", "--paginate", "user/repos?affiliation=owner,collaborator&per_page=100", "--jq",
            ".[] | [.full_name, .owner.login, ((.topics // []) | index(\"" .. TOPIC .. "\") != null), .pushed_at[0:10]] | @tsv" }, nil, function(rep)
        local items = {}
        for line in (inv.stdout or ""):gmatch("[^\n]+") do
          local id, slug, from = line:match("^(%d+)\t([^\t]+)\t(.*)")
          if id then
            items[#items + 1] = { icon = "\u{f01ee}", icon_hl = "GvAdded", label = ("%s  (invitation from %s: accept and open)"):format(slug, from),
              run = function()
                run({ "gh", "api", "-X", "PATCH", "user/repository_invitations/" .. id }, nil, function(a)
                  if a.code ~= 0 then return notify("Couldn't accept:\n" .. err_of(a), vim.log.levels.ERROR) end
                  M.clone(slug)
                end)
              end }
          end
        end
        local list = {}
        for line in (rep.stdout or ""):gmatch("[^\n]+") do
          local slug, owner, tagged, date = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t?(.*)")
          -- others' repos you were invited to, and your own repos shared from gv
          if slug and (owner ~= user.login or tagged == "true") then list[#list + 1] = { slug = slug, owner = owner, date = date } end
        end
        table.sort(list, function(a, b) return a.date > b.date end)
        if #items > 0 and #list > 0 then items[#items + 1] = "-" end
        for _, p in ipairs(list) do
          items[#items + 1] = { icon = "\u{f0219}", label = ("%s  (%s)"):format(p.slug, p.owner == user.login and ("yours, " .. p.date) or ("shared by " .. p.owner .. ", " .. p.date)),
            run = function() M.clone(p.slug) end }
        end
        if #items == 0 then
          items[#items + 1] = { icon = "\u{f0214}", label = "Nothing shared with " .. user.login .. " yet (ask them to invite you)", disabled = true }
        end
        items[#items + 1] = "-"
        items[#items + 1] = { icon = "\u{f0337}", label = "From a link (github.com/owner/name)…", key = "l", run = function()
          vim.ui.input({ prompt = "GitHub link or owner/name" }, function(v)
            local slug = v and (slug_of(v) or vim.trim(v):match("^[%w%-_.]+/[%w%-_.]+$"))
            if slug then M.clone(slug) elseif v and v ~= "" then notify("Not a GitHub project: " .. v, vim.log.levels.WARN) end
          end)
        end }
        menu.open({ title = "Open a shared project", anchor = "center", items = items })
      end)
    end)
  end)
end

-- ── the menu (Share button, Space l o) ─────────────────────────────────────

function M.menu(anchor)
  local root = M.root()
  M.remote(root, function(slug)
    local items
    if slug then
      local n = M._behind[root] or 0
      items = {
        { icon = "\u{f04e6}", label = "Sync" .. (n > 0 and ("  (" .. n .. " new from the others)") or "  (get theirs, send yours)"), key = "s", run = function() M.sync(root) end },
        { icon = "\u{f0014}", label = "Invite someone…", key = "i", run = function() with_github(function() M.invite(root, slug) end) end },
        { icon = "\u{f000e}", label = "People with access…", key = "p", run = function() with_github(function() M.people(root, slug) end) end },
        { icon = "\u{f018f}", label = "Copy the how-to-open message", key = "c", run = function()
          vim.fn.setreg("+", invite_text(root, slug)); notify("Copied: paste it in a mail or chat") end },
        { icon = "\u{f02a4}", label = "Open on GitHub (history, settings)", key = "g", run = function() vim.ui.open("https://github.com/" .. slug) end },
        { icon = "\u{f0e09}", label = "Check for changes now", key = "k", run = function() M._checked[root] = nil; M.check(root, false) end },
        "-",
        { icon = "\u{f0770}", label = "Open a shared project…", key = "o", run = M.open_shared },
      }
    else
      items = {
        { icon = "\u{f0497}", label = root and ("Share " .. vim.fs.basename(root) .. " on GitHub (private)…") or "Share: open a file of the project first",
          key = "s", disabled = not root, run = function() M.share(root) end },
        { icon = "\u{f0770}", label = "Open a shared project…", key = "o", run = M.open_shared },
        "-",
        { icon = "\u{f0214}", label = "Only people you invite can see it; build files stay out", disabled = true },
      }
    end
    menu.open({ title = "Share" .. (slug and (": " .. slug) or ""), anchor = anchor or "center", items = items })
  end)
end

-- the window's Share button (runner/gvwindow.py)
_G.GvShareMenu = function()
  vim.schedule(function() M.menu("center") end)
  return ""
end

vim.keymap.set("n", "<leader>lo", function() M.menu() end, { desc = "Share / Sync the LaTeX project (GitHub, private)" })
vim.api.nvim_create_user_command("GvShare", function(o)
  local a = o.args
  if a == "sync" then M.sync() elseif a == "open" then M.open_shared() elseif a == "invite" then M.menu() else M.menu() end
end, { nargs = "?", complete = function() return { "sync", "open", "invite" } end, desc = "Share the LaTeX project" })
vim.cmd([[
  amenu PopUp.Share\ /\ Sync… <cmd>lua require("gv.share").menu("cursor")<cr>
]])

return M
