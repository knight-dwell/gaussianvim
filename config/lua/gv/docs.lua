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
M.pydoc = { "scipy" }               -- documented from the installed package

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
          out[#out + 1] = { text = e.name .. " " .. label, name = e.name, kind = e.type, slug = name, path = e.path, label = label }
        end
      end
    elseif name:match("^pydoc%-.+%.json$") then
      local ok, idx = pcall(vim.json.decode, read(DIR .. "/" .. name) or "")
      if ok and type(idx) == "table" then
        local label = name:match("^pydoc%-(.+)%.json$")
        for _, e in ipairs(idx) do
          out[#out + 1] = { text = e.name .. " " .. label, name = e.name, kind = e.type, pydoc = true, label = label }
        end
      end
    end
  end
  M._entries = out
  return out
end

local dbs = {}
local function html_to_lines(html)
  if vim.fn.executable("pandoc") == 1 then
    local r = vim.system({ "pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none" }, { stdin = html, text = true }):wait()
    if r.code == 0 then return vim.split(r.stdout, "\n") end
  end
  local text = html:gsub("<br%s*/?>", "\n"):gsub("</p>", "\n\n"):gsub("<[^>]+>", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  return vim.split(text, "\n")
end

-- the page of an entry, as Markdown lines
function M.page(e)
  if e.pydoc then
    local r = vim.system({ python(), RUNNER .. "/gvpydoc.py", "show", e.name }, { text = true }):wait()
    return vim.split(r.stdout or "", "\n"), "rst"
  end
  if not dbs[e.slug] then
    local ok, db = pcall(vim.json.decode, read(DIR .. "/" .. e.slug .. "/db.json") or "{}")
    dbs[e.slug] = ok and db or {}
  end
  local key = e.path:gsub("#.*", "")
  local html = dbs[e.slug][key]
  if not html then return { "(page not found: " .. e.path .. ")" }, "markdown" end
  return html_to_lines(html), "markdown"
end

local function open_page(e)
  local lines, ft = M.page(e)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype, vim.bo[buf].modifiable, vim.bo[buf].bufhidden = ft, false, "wipe"
  local w, h = math.min(110, vim.o.columns - 6), vim.o.lines - 6
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = 2, col = math.floor((vim.o.columns - w) / 2), width = w, height = h,
    border = "rounded", style = "minimal", title = { { " \u{f02d} " .. e.name .. "  ·  " .. e.label .. " ", "FloatTitle" } },
    footer = { { " q close · / search · gx open link ", "FloatFooter" } }, footer_pos = "right",
  })
  vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].conceallevel = true, true, 2
  -- jump to the anchor (#numpy.linspace) when the page has many entries
  local anchor = (e.path or ""):match("#(.+)$")
  if anchor then
    local last = anchor:match("([^.]+)$") or anchor
    for i, l in ipairs(lines) do
      if l:find(last, 1, true) and l:match("^[#`*]") then pcall(vim.api.nvim_win_set_cursor, win, { i, 0 }); break end
    end
  end
  for _, k in ipairs({ "q", "<Esc>" }) do vim.keymap.set("n", k, "<cmd>close<cr>", { buffer = buf, nowait = true }) end
end

function M.search(query)
  local list = entries()
  if #list == 0 then
    return require("gv.menu").confirm("No docs downloaded yet. Get NumPy, Matplotlib, Python, SciPy, pandas, LaTeX (~150 MB)?",
      "Download", function() M.install(nil, function() M.search(query) end) end)
  end
  Snacks.picker.pick({
    title = "Docs: " .. table.concat(vim.tbl_keys((function() local s = {} for _, e in ipairs(list) do s[e.label] = true end return s end)()), " · "),
    items = list, pattern = query,
    format = function(item) return { { item.name, "Function" }, { "  " .. (item.kind or ""), "Comment" }, { "  " .. item.label, "Special" } } end,
    preview = function(ctx)
      local lines, ft = M.page(ctx.item)
      ctx.preview:set_lines(lines)
      ctx.preview:highlight({ ft = ft })
    end,
    confirm = function(picker, item)
      picker:close()
      if item then vim.schedule(function() open_page(item) end) end
    end,
  })
end

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
