-- The git dropdown: click the branch name in the status line, or Space g m.
-- Pops up above the status line (like VS Code's status bar menus):
--   Source control (the card) · Commit · Sync · Push · Pull · Fetch ·
--   Stage / unstage all · Switch / new branch · History · Changed files ›
local git = require("gv.git")
local menu = require("gv.menu")
local M = {}

local CODE = { M = { "\u{f0214}", "GvModified" }, A = { "\u{f0752}", "GvAdded" }, D = { "\u{f0a7a}", "GvDeleted" },
  R = { "\u{f0453}", "GvModified" }, ["?"] = { "\u{f0613}", "GvUntracked" }, U = { "\u{f0026}", "GvDeleted" } }

-- one changed file → Open / Diff / Stage or Unstage / Discard
local function file_menu(root, f, staged)
  return {
    title = f.path,
    items = {
      { icon = "\u{f03cc}", label = "Open", key = "o", run = function() git.open_file(root, f, false) end },
      { icon = "\u{f0c51}", label = "Show changes (diff)", key = "d", disabled = f.code == "?",
        run = function() git.open_file(root, f, true, staged) end },
      staged and { icon = "\u{f0374}", label = "Unstage", key = "u", run = function() git.unstage(root, f.path) end }
        or { icon = "\u{f0415}", label = "Stage", key = "s", run = function() git.stage(root, f.path) end },
      "-",
      { icon = "\u{f054c}", label = f.code == "?" and "Delete this new file" or "Discard changes", key = "x", disabled = staged,
        run = function()
          menu.confirm(f.code == "?" and ("Delete " .. f.path .. "?") or ("Discard changes to " .. f.path .. "?"),
            f.code == "?" and "Delete" or "Discard", function() git.discard(root, f) end)
        end },
    },
  }
end

local function files_menu(root, s)
  local items = {}
  local function add(list, staged)
    for _, f in ipairs(list) do
      local c = CODE[f.code] or { "\u{f0214}", "GvModified" }
      items[#items + 1] = { icon = c[1], icon_hl = c[2], label = f.path .. (staged and "  (staged)" or ""),
        submenu = function() return file_menu(root, f, staged) end }
    end
  end
  add(s.staged, true)
  add(s.changes, false)
  if #items == 0 then items = { { icon = "\u{f012c}", label = "No changes", disabled = true } } end
  return { title = "Changed files", items = items }
end

local function commit(root, s)
  local function ask(stage_all)
    vim.ui.input({ prompt = "Commit message" }, function(msg)
      if msg and vim.trim(msg) ~= "" then git.commit(root, vim.trim(msg), stage_all) end
    end)
  end
  if #s.staged > 0 then return ask(false) end
  if #s.changes == 0 then return vim.notify("Nothing to commit", vim.log.levels.INFO, { title = "Git" }) end
  menu.open({
    title = "Nothing is staged", anchor = "center",
    items = {
      { icon = "\u{f012c}", label = "Stage everything and commit", key = "s", run = function() ask(true) end },
      { icon = "\u{f0156}", label = "Cancel", key = "n" },
    },
  })
end

local function items(root, s)
  local n = #s.staged + #s.changes
  local sync = ("Sync changes   ↓%d ↑%d"):format(s.behind, s.ahead)
  return {
    { icon = "\u{f02a2}", label = "Source control…", key = "G", run = function() require("gv.scm").open() end },
    "-",
    { icon = "\u{f012c}", label = "Commit…", key = "c", run = function() commit(root, s) end },
    { icon = "\u{f04e6}", label = sync, key = "S", run = function() git.sync(root) end },
    { icon = "\u{f0167}", label = "Push", key = "P", run = function() git.push(root) end },
    { icon = "\u{f0162}", label = "Pull", key = "p", run = function() git.pull(root) end },
    { icon = "\u{f01da}", label = "Fetch", key = "f", run = function() git.fetch(root) end },
    "-",
    { icon = "\u{f0415}", label = "Stage all changes", key = "s", disabled = #s.changes == 0, run = function() git.stage(root) end },
    { icon = "\u{f0374}", label = "Unstage all", key = "u", disabled = #s.staged == 0, run = function() git.unstage(root) end },
    "-",
    { icon = "\u{e725}", label = "Switch branch…", key = "b", run = function() git.branches(root) end },
    { icon = "\u{f14ca}", label = "New branch…", key = "n", run = function() git.new_branch(root) end },
    { icon = "\u{f02da}", label = "History", key = "H", run = function() git.history(root) end },
    { icon = "\u{f0dc8}", label = ("Changed files (%d)"):format(n), submenu = function() return files_menu(root, s) end },
  }
end

function M.open(anchor)
  local root = git.root()
  if not root then
    return menu.open({
      title = "Git", anchor = anchor or "statusline",
      items = {
        { icon = "\u{f0026}", label = "Not a git repository", disabled = true },
        { icon = "\u{f02a2}", label = "Initialize repository here", key = "i", run = function() git.init(vim.uv.cwd()) end },
      },
    })
  end
  git.status(root, function(s)
    if not s then return end
    local head = "\u{e725} " .. s.branch .. (s.ahead > 0 and ("  ↑" .. s.ahead) or "") .. (s.behind > 0 and ("  ↓" .. s.behind) or "")
    menu.open({ title = head, anchor = anchor or "statusline", items = items(root, s), min_width = 34 })
  end)
end

M.files_menu, M.file_menu, M.commit = files_menu, file_menu, commit
return M
