-- Search Stack Exchange from gv: Stack Overflow, TeX, Physics, Mathematics,
-- Unix, Ask Ubuntu. Results show with their score; Enter opens the question
-- and its best answers (newest votes first) right in gv; o opens it in the browser.
--
--   Space s x   search (pick the site; in a .tex file TeX.SE comes first). The
--               query starts with the error on this line, or your selection.
local M = {}
local API = "https://api.stackexchange.com/2.3"
M.sites = {
  { id = "stackoverflow", name = "Stack Overflow (code)" },
  { id = "tex", name = "TeX - LaTeX" },
  { id = "physics", name = "Physics" },
  { id = "math", name = "Mathematics" },
  { id = "unix", name = "Unix & Linux" },
  { id = "askubuntu", name = "Ask Ubuntu" },
}

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Stack Exchange" }) end

local function get(url, cb)
  vim.system({ "curl", "-fsSL", "--compressed", "--max-time", "20", url }, { text = true }, function(r)
    vim.schedule(function()
      local ok, data = pcall(vim.json.decode, r.stdout or "")
      if r.code ~= 0 or not ok then return notify("No answer from Stack Exchange (offline?)", vim.log.levels.WARN) end
      if data.error_message then return notify(data.error_message, vim.log.levels.WARN) end
      cb(data)
    end)
  end)
end

local function enc(s) return (s:gsub("[^%w%-_%.~ ]", function(c) return ("%%%02X"):format(c:byte()) end):gsub(" ", "+")) end
local function unhtml(s) return (s or ""):gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&") end
-- sites whose posts write maths as $...$ (MathJax): it is typeset in the reader
local MATH_SITES = { physics = true, math = true, mathoverflow = true }

-- keep $...$ / $$...$$ exactly as written (outside <pre>/<code>): swap them for
-- placeholders before pandoc and put them back after
local function protect_math(html)
  local store, out, pos = {}, {}, 1
  local function put(f, display)
    f = unhtml(f):gsub("%s+", " ")
    store[#store + 1] = { f = vim.trim(f), d = display }
    return ("GVMATH%s%dX"):format(display and "D" or "I", #store)
  end
  local function math_in(chunk)
    chunk = chunk:gsub("%$%$(.-)%$%$", function(f) return put(f, true) end)
    chunk = chunk:gsub("\\%[(.-)\\%]", function(f) return put(f, true) end)
    return (chunk:gsub("%$([^%$]-)%$", function(f)
      if f:match("^%s*$") then return nil end
      return put(f, false)
    end))
  end
  while pos <= #html do
    local s, e = html:find("<pre.-</pre>", pos)
    local cs, ce = html:find("<code.-</code>", pos)
    if cs and (not s or cs < s) then s, e = cs, ce end
    if not s then out[#out + 1] = math_in(html:sub(pos)); break end
    out[#out + 1] = math_in(html:sub(pos, s - 1))
    out[#out + 1] = html:sub(s, e)
    pos = e + 1
  end
  return table.concat(out), store
end

local function md(html, with_math)
  html = html or ""
  local store
  if with_math then html, store = protect_math(html) end
  local text
  if vim.fn.executable("pandoc") == 1 then
    local r = vim.system({ "pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none" }, { stdin = html, text = true }):wait()
    if r.code == 0 then text = r.stdout end
  end
  text = text or unhtml(html:gsub("<[^>]+>", ""))
  if store then
    text = text:gsub("GVMATH([DI])(%d+)X", function(kind, n)
      local m = store[tonumber(n)]
      if not m then return "" end
      return kind == "D" and ("\n\n$$" .. m.f .. "$$\n\n") or ("$" .. m.f .. "$")
    end)
  end
  return vim.split(text, "\n")
end

-- the question and its answers as one HTML page for the rendered reader
local function reader_html(site, q, answers)
  local parts = { q.body or "", ("<div class=\"gvmeta\">score %d · %d answers</div>"):format(q.score, q.answer_count) }
  for _, a in ipairs(answers) do
    parts[#parts + 1] = ("<div class=\"gvpost\"><div class=\"gvmeta%s\">Answer · score %d%s</div>%s</div>")
      :format(a.is_accepted and " ok" or "", a.score, a.is_accepted and " · ✓ accepted" or "", a.body or "")
  end
  local dir = vim.fn.stdpath("cache") .. "/reader"
  vim.fn.mkdir(dir, "p")
  local file = ("%s/%s-%d.html"):format(dir, site, q.question_id)
  vim.fn.writefile(vim.split(table.concat(parts, "\n"), "\n"), file)
  return { "html", file, unhtml(q.title), q.link }
end

-- the question and its top answers in a reading window
local function open_question(site, q)
  get(("%s/questions/%d/answers?order=desc&sort=votes&site=%s&filter=withbody&pagesize=4"):format(API, q.question_id, site), function(data)
    local has_math = MATH_SITES[site]
    local lines = { "# " .. unhtml(q.title), "", ("score %d · %d answers · %s"):format(q.score, q.answer_count, q.link), "" }
    vim.list_extend(lines, md(q.body, has_math))
    for _, a in ipairs(data.items or {}) do
      vim.list_extend(lines, { "", "---", "", ("## Answer · score %d%s"):format(a.score, a.is_accepted and " · ✓ accepted" or ""), "" })
      vim.list_extend(lines, md(a.body, has_math))
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype, vim.bo[buf].modifiable, vim.bo[buf].bufhidden = "markdown", false, "wipe"
    local w = math.min(110, vim.o.columns - 6)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", row = 2, col = math.floor((vim.o.columns - w) / 2), width = w, height = vim.o.lines - 6,
      border = "rounded", style = "minimal", title = { { " " .. site .. " ", "FloatTitle" } },
      footer = { { " q back to the results · Q close · p rendered · o open in browser ", "FloatFooter" } }, footer_pos = "right",
    })
    local rargs = reader_html(site, q, data.items or {})
    require("gv.reader").auto(rargs)
    vim.keymap.set("n", "p", function() require("gv.reader").open(rargs) end, { buffer = buf, nowait = true })
    vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].conceallevel = true, true, 2
    -- q / Backspace: back to the list of results, where you were; Q / Esc: close
    for _, k in ipairs({ "q", "<BS>" }) do
      vim.keymap.set("n", k, function() vim.cmd.close(); Snacks.picker.resume() end, { buffer = buf, nowait = true })
    end
    for _, k in ipairs({ "Q", "<Esc>" }) do vim.keymap.set("n", k, "<cmd>close<cr>", { buffer = buf, nowait = true }) end
    if has_math then require("gv.mathrender").render(buf) end
    vim.keymap.set("n", "o", function() vim.ui.open(q.link) end, { buffer = buf, nowait = true })
  end)
end

-- up to 100 results per page (the API's maximum; one request either way);
-- "Load more results" at the end fetches the next 100
function M.query(site, text, page, prev)
  page = page or 1
  local url = ("%s/search/advanced?order=desc&sort=relevance&q=%s&site=%s&filter=withbody&pagesize=100&page=%d")
    :format(API, enc(text), site, page)
  notify(page == 1 and ("Searching " .. site .. "…") or ("Loading more results (page " .. page .. ")…"))
  get(url, function(data)
    local items = prev or {}
    if items[#items] and items[#items].more then table.remove(items) end
    for _, q in ipairs(data.items or {}) do
      items[#items + 1] = { text = unhtml(q.title), q = q }
    end
    if #items == 0 then return notify("Nothing found for: " .. text) end
    if data.has_more then items[#items + 1] = { text = "Load more results", more = page + 1 } end
    Snacks.picker.pick({
      title = ("%s: %s  (%d)"):format(site, text, #items - (data.has_more and 1 or 0)), items = items,
      format = function(item)
        if item.more then return { { "  \u{f0415} ", "Special" }, { "Load more results…", "Special" } } end
        local q = item.q
        return { { ("%4d "):format(q.score), q.is_answered and "DiagnosticOk" or "Comment" }, { item.text },
          { ("  %d answers"):format(q.answer_count), "Comment" } }
      end,
      preview = function(ctx)
        if ctx.item.more then return ctx.preview:set_lines({ "", "  Enter: the next 100 results" }) end
        ctx.preview:set_lines(md(ctx.item.q.body, MATH_SITES[site]))
        ctx.preview:highlight({ ft = "markdown" })
      end,
      actions = { open_browser = function(_, item) if item and item.q then vim.ui.open(item.q.link) end end },
      win = { input = { keys = { ["<C-o>"] = { "open_browser", mode = { "i", "n" } } } } },
      confirm = function(picker, item)
        picker:close()
        if not item then return end
        if item.more then return M.query(site, text, item.more, items) end
        open_question(site, item.q)
      end,
    })
  end)
end

-- what to search for: the selection, else the error on this line, else the word
local function default_query(visual)
  if visual then
    local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    return table.concat(vim.api.nvim_buf_get_text(0, s[2] - 1, s[3] - 1, e[2] - 1, math.min(e[3], #vim.fn.getline(e[2])), {}), " ")
  end
  local d = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })[1]
  if d then return (d.message:gsub("\n.*", "")) end
  return vim.fn.expand("<cword>")
end

function M.search(visual)
  local text = default_query(visual)
  local sites = vim.deepcopy(M.sites)
  local ft = vim.bo.filetype
  if ft == "tex" or ft == "plaintex" then table.insert(sites, 1, table.remove(sites, 2)) end
  local items = {}
  for i, s in ipairs(sites) do
    items[#items + 1] = { icon = "\u{f04cc}", label = s.name, key = tostring(i), run = function()
      vim.schedule(function()
        Snacks.input({ prompt = "Search " .. s.name, default = text }, function(q)
          if q and vim.trim(q) ~= "" then M.query(s.id, q) end
        end)
      end)
    end }
  end
  require("gv.menu").open({ title = "Stack Exchange", anchor = "center", items = items })
end

return M
