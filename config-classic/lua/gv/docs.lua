-- Offline documentation inside gv: NumPy, Matplotlib, Python, pandas, LaTeX,
-- Fortran, Bash (from DevDocs) and SciPy (from the installed package, like help()).
--
--   Space s d   search all the docs (type numpy.linspace, savefig, quad, \frac, ...)
--   Space s D   docs for the word under the cursor
--   :GvDocs install numpy matplotlib ...   add / update DevDocs sets (:GvDocs list shows them)
--
-- The sets are downloaded once into ~/.local/share/gaussianvim/docs (the
-- installer does it; Space s d offers it the first time).
local M = {}
local DIR = vim.fn.stdpath("data") .. "/docs"
local RUNNER = vim.fn.stdpath("config") .. "/runner"
M.default = { "python", "numpy", "matplotlib", "pandas", "latex", "gnu_fortran", "bash" }
M.pydoc = { "scipy" }
local PREFIXED = { numpy = true, matplotlib = true, pandas = true }               -- documented from the installed package

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Docs" }) end
local function read(p) local f = io.open(p, "r"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

local function python()
  for _, env in ipairs({ vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX }) do
    if env and env ~= "" and vim.fn.executable(env .. "/bin/python") == 1 then return env .. "/bin/python" end
  end
  return "python3"
end

-- DevDocs slug for a name: the release matching your installed version if there is one
local function resolve(names, list)
  local out = {}
  for _, name in ipairs(names) do
    local want
    if name == "python" or name == "numpy" or name == "pandas" then
      local code = name == "python" and "import sys;print('%d.%d'%sys.version_info[:2])"
        or ("import " .. name .. ";print('.'.join(" .. name .. ".__version__.split('.')[:2]))")
      local r = vim.system({ python(), "-c", code }, { text = true }):wait()
      want = vim.trim(r.stdout or "")
    end
    local pick
    for _, d in ipairs(list) do
      if d.slug == name or d.slug:match("^" .. vim.pesc(name) .. "~") then
        if want and want ~= "" and d.slug == name .. "~" .. want then pick = d.slug; break end
        if want and want ~= "" and name ~= "python" and d.slug == name .. "~" .. want:match("^%d+") then pick = d.slug; break end
        pick = pick or d.slug
      end
    end
    if pick then out[#out + 1] = pick end
  end
  return out
end

function M.install(names, done)
  names = (names and #names > 0) and names or M.default
  vim.fn.mkdir(DIR, "p")
  notify("Downloading docs: " .. table.concat(names, ", ") .. " (a few minutes the first time)")
  vim.system({ "curl", "-fsSL", "--max-time", "60", "https://devdocs.io/docs.json" }, { text = true }, function(r)
    vim.schedule(function()
      local ok, list = pcall(vim.json.decode, r.stdout or "")
      if r.code ~= 0 or not ok then return notify("Couldn't reach devdocs.io", vim.log.levels.ERROR) end
      local slugs = resolve(names, list)
      local i = 0
      local function next_one()
        i = i + 1
        local slug = slugs[i]
        if not slug then
          M._entries = nil
          notify("Docs ready: " .. table.concat(slugs, ", ") .. ". Space s d searches them")
          if done then done() end
          return
        end
        local d = DIR .. "/" .. slug
        vim.fn.mkdir(d, "p")
        local base = "https://documents.devdocs.io/" .. slug
        vim.system({ "sh", "-c", ('curl -fsSL --compressed "%s/index.json" -o "%s/index.json" && curl -fsSL --compressed "%s/db.json" -o "%s/db.json"')
          :format(base, d, base, d) }, {}, function(c)
          vim.schedule(function()
            if c.code ~= 0 then notify("Couldn't download " .. slug, vim.log.levels.WARN) end
            next_one()
          end)
        end)
      end
      next_one()
    end)
  end)
  -- SciPy & co: an index of the installed package
  for _, pkg in ipairs(M.pydoc) do
    vim.system({ python(), RUNNER .. "/gvpydoc.py", "index", pkg }, { text = true }, function(r)
      if r.code == 0 and (r.stdout or ""):match("^%[") then
        local f = io.open(DIR .. "/pydoc-" .. pkg .. ".json", "w")
        if f then f:write(r.stdout); f:close() end
      end
    end)
  end
end

-- every entry of every installed set
local function entries()
  if M._entries then return M._entries end
  local out = {}
  for name, kind in vim.fs.dir(DIR) do
    if kind == "directory" then
      local ok, idx = pcall(vim.json.decode, read(DIR .. "/" .. name .. "/index.json") or "")
      if ok and type(idx) == "table" then
        local label = name:gsub("~.*", "")
        for _, e in ipairs(idx.entries or {}) do
          -- DevDocs leaves the package off sub-modules (linalg.det()): put it back, so
          -- numpy.linalg / matplotlib.pyplot are trees and searchable by their full name
          local full = e.name:gsub("%(%)$", "")
          if PREFIXED[label] and full:sub(1, #label + 1) ~= label .. "." then full = label .. "." .. full end
          out[#out + 1] = { text = full .. " " .. (e.type or ""), name = full, kind = e.type, slug = name, path = e.path, label = label, summary = e.type or "" }
        end
      end
    elseif name:match("^pydoc%-.+%.json$") then
      local ok, idx = pcall(vim.json.decode, read(DIR .. "/" .. name) or "")
      if ok and type(idx) == "table" then
        local label = name:match("^pydoc%-(.+)%.json$")
        for _, e in ipairs(idx) do
          out[#out + 1] = { text = e.name .. " " .. (e.summary or ""), name = e.name, kind = e.type, pydoc = true, label = label, summary = e.summary or "" }
        end
      end
    end
  end
  M._entries = out
  return out
end

-- pages ---------------------------------------------------------------------------
-- built in the background (gv never freezes) and kept, so going back is instant

local dbs, pages = {}, {}

-- LaTeX in the HTML (\( \), \[ \]) back to $...$ for the maths renderer
local function fix_math(text)
  text = text:gsub("\\%[(.-)\\%]", function(f) return "\n\n$$" .. f:gsub("%s+", " ") .. "$$\n\n" end)
  return (text:gsub("\\%((.-)\\%)", "$%1$"))
end

local function html_to_md(html, cb)
  if vim.fn.executable("pandoc") == 1 then
    vim.system({ "pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none" }, { stdin = html, text = true }, function(r)
      vim.schedule(function() cb(vim.split(fix_math(r.code == 0 and r.stdout or html), "\n")) end)
    end)
  else
    local text = html:gsub("<br%s*/?>", "\n"):gsub("</p>", "\n\n"):gsub("<[^>]+>", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
    cb(vim.split(text, "\n"))
  end
end

local function key(e) return (e.slug or e.label) .. ":" .. e.name end

-- the page of an entry as Markdown lines (cb(lines))
function M.page_async(e, cb)
  local k = key(e)
  if pages[k] then return cb(pages[k]) end
  local function done(lines) pages[k] = lines; cb(lines) end
  if e.pydoc then
    vim.system({ python(), RUNNER .. "/gvpydoc.py", "md", e.name }, { text = true }, function(r)
      vim.schedule(function() done(vim.split(r.stdout ~= "" and r.stdout or ("# " .. e.name .. "\n\n(no page)"), "\n")) end)
    end)
    return
  end
  if not dbs[e.slug] then
    local ok, db = pcall(vim.json.decode, read(DIR .. "/" .. e.slug .. "/db.json") or "{}")
    dbs[e.slug] = ok and db or {}
  end
  local html = dbs[e.slug][(e.path or ""):gsub("#.*", "")]
  if not html then return done({ "(page not found: " .. tostring(e.path) .. ")" }) end
  html_to_md(html, done)
end

-- for tests / scripts: wait for a page
function M.page(e)
  local res
  M.page_async(e, function(l) res = l end)
  vim.wait(20000, function() return res ~= nil end, 20)
  return res or {}, "markdown"
end

local function open_page(e)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  loading " .. e.name .. " …" })
  vim.bo[buf].filetype, vim.bo[buf].bufhidden = "markdown", "wipe"
  local w, h = math.min(110, vim.o.columns - 6), vim.o.lines - 6
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = 2, col = math.floor((vim.o.columns - w) / 2), width = w, height = h,
    border = "rounded", style = "minimal", title = { { " \u{f02d} " .. e.name .. "  ·  " .. e.label .. " ", "FloatTitle" } },
    footer = { { " q back to the list · Q close · / search · gx open link ", "FloatFooter" } }, footer_pos = "right",
  })
  vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].conceallevel = true, true, 2
  for _, k in ipairs({ "q", "<BS>" }) do
    vim.keymap.set("n", k, function() vim.cmd.close(); Snacks.picker.resume() end, { buffer = buf, nowait = true })
  end
  for _, k in ipairs({ "Q", "<Esc>" }) do vim.keymap.set("n", k, "<cmd>close<cr>", { buffer = buf, nowait = true }) end
  M.page_async(e, function(lines)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    -- jump to the anchor (#numpy.linspace) when the page holds many entries
    local anchor = (e.path or ""):match("#(.+)$")
    if anchor and vim.api.nvim_win_is_valid(win) then
      local last = anchor:match("([^.]+)$") or anchor
      for i, l in ipairs(lines) do
        if l:find(last, 1, true) and l:match("^[#`*]") then pcall(vim.api.nvim_win_set_cursor, win, { i, 0 }); break end
      end
    end
    require("gv.mathrender").render(buf)
  end)
end

-- the picker ----------------------------------------------------------------------

local children
local function preview(ctx)
  local item = ctx.item
  if item.up then return ctx.preview:set_lines({ "", "  back to " .. item.up }) end
  if not (item.pydoc or item.slug) then           -- a folder without a page: what is inside
    local lines = { "# " .. item.name, "" }
    for _, c in ipairs(children(M._entries or {}, item.name)) do lines[#lines + 1] = "- `" .. c.short .. "`  " .. (c.summary or "") end
    ctx.preview:set_lines(lines)
    return ctx.preview:highlight({ ft = "markdown" })
  end
  ctx.preview:set_lines({ "", "  loading …" })
  M.page_async(item, function(lines)
    if ctx.picker.closed or ctx.picker:current() ~= item then return end
    ctx.preview:set_lines(lines)
    ctx.preview:highlight({ ft = "markdown" })
  end)
end

local function fmt(item)
  if item.up then return { { "\u{f0743}  .. ", "Directory" }, { "back to " .. item.up, "Comment" } } end
  local icon = item.folder and "\u{f024b}  " or item.kind == "class" and "\u{f01a7}  " or "\u{f0295}  "
  local name = item.short or item.name
  return { { icon, item.folder and "Directory" or "Function" }, { name, item.folder and "Directory" or "Normal" },
    { "  " .. (item.summary ~= "" and item.summary or item.kind or ""), "Comment" }, { "  " .. item.label, "Special" } }
end

-- children of a dotted name: entries one level below it (functions, classes, sub-modules)
children = function(list, prefix)
  local out, folders = {}, {}
  local p = prefix .. "."
  for _, e in ipairs(list) do
    if e.name:sub(1, #p) == p and e.name ~= prefix then
      local rest = e.name:sub(#p + 1)
      local head = rest:match("^([^.]+)%.")
      if head then
        folders[head] = true                    -- something deeper: show its folder
      else
        out[#out + 1] = vim.tbl_extend("force", {}, e, { short = rest, folder = e.kind == "module" })
      end
    end
  end
  local have = {}
  for _, e in ipairs(out) do have[e.short] = true end
  -- hide sub-modules that only repeat what is here already (SciPy's old
  -- scipy.integrate.quadpack, odepack, ...: kept for backward compatibility)
  local function redundant(sub)
    local q, any = p .. sub .. ".", false
    for _, e in ipairs(list) do
      if e.name:sub(1, #q) == q then
        any = true
        if not have[e.name:sub(#q + 1)] then return false end
      end
    end
    return any
  end
  for i = #out, 1, -1 do
    if out[i].folder and redundant(out[i].short) then table.remove(out, i) end
  end
  for head in pairs(folders) do if redundant(head) then folders[head] = nil end end
  for head in pairs(folders) do
    if not have[head] then
      out[#out + 1] = { name = p .. head, short = head, folder = true, kind = "module", label = "", summary = "", text = p .. head }
    end
  end
  table.sort(out, function(a, b)
    if (a.folder or false) ~= (b.folder or false) then return a.folder end
    return a.short:lower() < b.short:lower()
  end)
  return out
end

local function has_children(list, name)
  local p = name .. "."
  for _, e in ipairs(list) do if e.name:sub(1, #p) == p then return true end end
  return false
end

local open_tree

local function confirm(picker, item)
  if not item then return end
  picker:close()
  vim.schedule(function()
    local list = M._entries or {}
    if item.up then return open_tree(item.up) end
    if item.read then return open_page(item.read) end
    if has_children(list, item.name) then return open_tree(item.name, item) end
    open_page(item)
  end)
end

-- a module as a tree: its sub-modules (folders) and functions; Enter goes in,
-- ".." goes up, the first line reads the module's own page
open_tree = function(name, module_item)
  local list = M._entries or {}
  local items = {}
  local parent = name:match("^(.+)%.[^.]+$")
  if parent then items[#items + 1] = { up = parent, text = ".. " .. parent } end
  module_item = module_item or (function()
    for _, e in ipairs(list) do if e.name == name then return e end end
  end)()
  if module_item then
    items[#items + 1] = vim.tbl_extend("force", {}, module_item, { short = name .. "  (read the module page)", read = module_item })
  end
  for _, c in ipairs(children(list, name)) do
    c.text = c.short                       -- in a tree you type a name, not a description
    items[#items + 1] = c
  end
  Snacks.picker.pick({
    title = "\u{f024b} " .. name, items = items, format = function(item) return fmt(item) end,
    preview = preview, confirm = confirm,
  })
end

function M.search(query)
  local list = entries()
  if #list == 0 then
    return require("gv.menu").confirm("No docs downloaded yet. Get NumPy, Matplotlib, Python, SciPy, pandas, LaTeX (~150 MB)?",
      "Download", function() M.install(nil, function() M.search(query) end) end)
  end
  local labels = {}
  for _, e in ipairs(list) do labels[e.label] = true end
  Snacks.picker.pick({
    title = "Docs: " .. table.concat(vim.tbl_keys(labels), " · ") .. "   (Enter on a module: its functions)",
    items = list, pattern = query, format = function(item) return fmt(item) end,
    preview = preview, confirm = confirm,
  })
end
M.tree = function(name) entries(); open_tree(name) end

vim.api.nvim_create_user_command("GvDocs", function(o)
  local args = vim.split(o.args, "%s+", { trimempty = true })
  if args[1] == "install" then
    table.remove(args, 1)
    M.install(args)
  elseif args[1] == "list" then
    local have = {}
    for n in vim.fs.dir(DIR) do have[#have + 1] = n end
    notify("Installed: " .. table.concat(have, ", ") .. "\nAdd more: :GvDocs install julia sympy ... (names from devdocs.io)")
  else
    M.search(o.args ~= "" and o.args or nil)
  end
end, { nargs = "*", desc = "Offline docs: search, or install <names>" })

return M
