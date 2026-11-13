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
local function md(html)
  if vim.fn.executable("pandoc") == 1 then
    local r = vim.system({ "pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none" }, { stdin = html or "", text = true }):wait()
    if r.code == 0 then return vim.split(r.stdout, "\n") end
  end
  return vim.split(unhtml((html or ""):gsub("<[^>]+>", "")), "\n")
end

-- the question and its top answers in a reading window
local function open_question(site, q)
  get(("%s/questions/%d/answers?order=desc&sort=votes&site=%s&filter=withbody&pagesize=4"):format(API, q.question_id, site), function(data)
    local lines = { "# " .. unhtml(q.title), "", ("score %d · %d answers · %s"):format(q.score, q.answer_count, q.link), "" }
    vim.list_extend(lines, md(q.body))
    for _, a in ipairs(data.items or {}) do
      vim.list_extend(lines, { "", "---", "", ("## Answer · score %d%s"):format(a.score, a.is_accepted and " · ✓ accepted" or ""), "" })
      vim.list_extend(lines, md(a.body))
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype, vim.bo[buf].modifiable, vim.bo[buf].bufhidden = "markdown", false, "wipe"
    local w = math.min(110, vim.o.columns - 6)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", row = 2, col = math.floor((vim.o.columns - w) / 2), width = w, height = vim.o.lines - 6,
      border = "rounded", style = "minimal", title = { { " " .. site .. " ", "FloatTitle" } },
      footer = { { " q close · o open in browser ", "FloatFooter" } }, footer_pos = "right",
    })
    vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].conceallevel = true, true, 2
    for _, k in ipairs({ "q", "<Esc>" }) do vim.keymap.set("n", k, "<cmd>close<cr>", { buffer = buf, nowait = true }) end
    vim.keymap.set("n", "o", function() vim.ui.open(q.link) end, { buffer = buf, nowait = true })
  end)
end

function M.query(site, text)
  local url = ("%s/search/advanced?order=desc&sort=relevance&q=%s&site=%s&filter=withbody&pagesize=25"):format(API, enc(text), site)
  notify("Searching " .. site .. "…")
  get(url, function(data)
    local items = {}
    for _, q in ipairs(data.items or {}) do
      items[#items + 1] = { text = unhtml(q.title), q = q }
    end
    if #items == 0 then return notify("Nothing found for: " .. text) end
    Snacks.picker.pick({
      title = site .. ": " .. text, items = items,
      format = function(item)
        local q = item.q
        return { { ("%4d "):format(q.score), q.is_answered and "DiagnosticOk" or "Comment" }, { item.text },
          { ("  %d answers"):format(q.answer_count), "Comment" } }
      end,
      preview = function(ctx)
        ctx.preview:set_lines(md(ctx.item.q.body))
        ctx.preview:highlight({ ft = "markdown" })
      end,
      actions = { open_browser = function(_, item) if item then vim.ui.open(item.q.link) end end },
      win = { input = { keys = { ["<C-o>"] = { "open_browser", mode = { "i", "n" } } } } },
      confirm = function(picker, item)
        picker:close()
        if item then open_question(site, item.q) end
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
