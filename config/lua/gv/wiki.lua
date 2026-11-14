-- Wikipedia inside gv, online and offline:
--
--   Space s w   search Wikipedia (the word under the cursor / your selection first).
--               Online results come from en.wikipedia.org; the offline physics and
--               maths Wikipedia (Kiwix files in ~/.local/share/gaussianvim/wiki,
--               :GvWiki install) answers too, and alone when there is no internet.
--
-- Articles open in a reading window with the maths typeset (kitty):
--   Enter on a link   open that article      t   the sections, jump to one
--   q                 back (previous article, else the results)
--   Q / Esc           close                  o   open in the browser
--   p                 the rendered reader: equations + figures (lua/gv/reader.lua);
--                     opens by itself where the terminal can't draw pictures
local M = {}
local API = "https://en.wikipedia.org/w/api.php"
local UA = "GaussianVim/1.0 (offline physics editor)"
local ZIMDIR = vim.fn.stdpath("data") .. "/wiki"
local RUNNER = vim.fn.stdpath("config") .. "/runner"
M.zims = {
  { file = "wikipedia_en_physics_nopic_2026-10.zim", name = "Physics" },
  { file = "wikipedia_en_mathematics_nopic_2026-09.zim", name = "Mathematics" },
}

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Wikipedia" }) end
local function enc(s) return (s:gsub("[^%w%-_%.~ ]", function(c) return ("%%%02X"):format(c:byte()) end):gsub(" ", "+")) end

local function curl(url, cb)
  vim.system({ "curl", "-fsSL", "--compressed", "--max-time", "15", "-A", UA, url }, { text = true }, function(r)
    vim.schedule(function()
      local ok, data = pcall(vim.json.decode, r.stdout or "")
      cb(r.code == 0 and ok and data or nil)
    end)
  end)
end

local function offline_files()
  local out = {}
  for _, z in ipairs(M.zims) do
    if vim.uv.fs_stat(ZIMDIR .. "/" .. z.file) then out[#out + 1] = { path = ZIMDIR .. "/" .. z.file, name = z.name } end
  end
  return out
end

-- Markdown for gv: no image placeholders, links you can follow (wiki:Title)
local function tidy(md)
  md = md:gsub("!%b[]%b()", "")
  md = md:gsub("%[([^%]]+)%]%(([^%s%)]+) \"wikilink\"%)", function(text, target)
    if target:match("^Category:") or target:match("^File:") then return "" end
    return ("[%s](wiki:%s)"):format(text, target)
  end)
  md = md:gsub("\n%s*\n%s*\n+", "\n\n")
  return vim.split(md, "\n")
end

local function pandoc(input, from, cb)
  vim.system({ "pandoc", "-f", from, "-t", "gfm", "--wrap=none" }, { stdin = input, text = true }, function(r)
    vim.schedule(function() cb(r.code == 0 and r.stdout or nil) end)
  end)
end

-- an article as Markdown lines: cb(lines) or cb(nil)
local cache = {}
function M.article(item, cb)
  local key = (item.zim or "online") .. ":" .. item.title
  if cache[key] then return cb(cache[key]) end
  local function done(md)
    if not md then return cb(nil) end
    local lines = tidy(md)
    table.insert(lines, 1, "")
    table.insert(lines, 1, "# " .. item.title)
    cache[key] = lines
    cb(lines)
  end
  if item.zim then
    vim.system({ "python3", RUNNER .. "/gvwiki.py", "article", item.zim, item.path }, { text = true }, function(r)
      vim.schedule(function() done(r.code == 0 and r.stdout ~= "" and r.stdout or nil) end)
    end)
    return
  end
  curl(("%s?action=parse&page=%s&prop=wikitext&format=json&formatversion=2&redirects=1"):format(API, enc(item.title)), function(data)
    local text = data and data.parse and data.parse.wikitext
    if not text then return cb(nil) end
    pandoc(text, "mediawiki", done)
  end)
end

-- the reading window ------------------------------------------------------------

local history = {}

local function open_article(item)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  loading " .. item.title .. " …" })
  vim.bo[buf].filetype, vim.bo[buf].bufhidden = "markdown", "wipe"
  local w = math.min(110, vim.o.columns - 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = 2, col = math.floor((vim.o.columns - w) / 2), width = w, height = vim.o.lines - 6,
    border = "rounded", style = "minimal",
    title = { { " \u{f05ac} " .. item.title .. "  ·  " .. (item.source or "Wikipedia") .. " ", "FloatTitle" } },
    footer = { { " Enter follow link · t sections · p rendered · q back · Q close · o browser ", "FloatFooter" } }, footer_pos = "right",
  })
  local reader_args = item.zim and { "zim", item.zim, item.path or item.title } or { "wiki", item.title }
  require("gv.reader").auto(reader_args)
  vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].conceallevel = true, true, 2
  local function map(k, fn) vim.keymap.set("n", k, fn, { buffer = buf, nowait = true }) end
  map("q", function()
    vim.cmd.close()
    local prev = table.remove(history)
    if prev then open_article(prev) else Snacks.picker.resume() end
  end)
  map("<BS>", function() vim.cmd("normal q") end)
  for _, k in ipairs({ "Q", "<Esc>" }) do map(k, function() history = {}; vim.cmd.close() end) end
  map("o", function()
    vim.ui.open("https://en.wikipedia.org/wiki/" .. item.title:gsub(" ", "_"))
  end)
  map("p", function() require("gv.reader").open(reader_args) end)
  -- Enter on a [link](wiki:Title): that article
  map("<CR>", function()
    local line, col = vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2] + 1
    for s, target, e in line:gmatch("()%[[^%]]-%]%(wiki:([^%)]+)%)()") do
      if col >= s and col < e then
        history[#history + 1] = item
        vim.cmd.close()
        return open_article({ title = target:gsub("_", " "), zim = item.zim, path = item.zim and target or nil, source = item.source })
      end
    end
  end)
  -- t: jump to a section
  map("t", function()
    local items = {}
    for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      local hashes, title = l:match("^(#+)%s+(.+)")
      if hashes then items[#items + 1] = { text = title, line = i, depth = #hashes } end
    end
    Snacks.picker.pick({
      title = "Sections", items = items, layout = { preset = "select" },
      format = function(it) return { { string.rep("  ", it.depth - 1) .. it.text } } end,
      confirm = function(picker, it)
        picker:close()
        if it and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
          vim.api.nvim_win_set_cursor(win, { it.line, 0 })
          vim.cmd("normal! zt")
        end
      end,
    })
  end)
  M.article(item, function(lines)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "", "  Couldn't load " .. item.title .. " (offline? try the offline Wikipedia: :GvWiki install)" })
    vim.bo[buf].modifiable = false
    if not pcall(vim.treesitter.language.add, "latex") then require("gv.mathrender").render(buf) end
  end)
end

-- search ---------------------------------------------------------------------------

local function strip(s) return (s or ""):gsub("<[^>]+>", ""):gsub("&quot;", '"'):gsub("&#039;", "'"):gsub("&amp;", "&") end

function M.query(text)
  local items, pending = {}, 0
  local function show()
    pending = pending - 1
    if pending > 0 then return end
    if #items == 0 then return notify("Nothing found for: " .. text .. (#offline_files() == 0 and " (offline Wikipedia not installed: :GvWiki install)" or "")) end
    history = {}
    Snacks.picker.pick({
      title = "Wikipedia: " .. text, items = items,
      format = function(it)
        return { { it.zim and "\u{f01bc} " or "\u{f059f} ", it.zim and "Special" or "Directory" }, { it.title, "Title" },
          { "  " .. (it.snippet or ""), "Comment" } }
      end,
      preview = function(ctx)
        local it = ctx.item
        ctx.preview:set_lines({ "", "  loading …" })
        M.article(it, function(lines)
          if ctx.picker.closed or ctx.picker:current() ~= it then return end
          ctx.preview:set_lines(lines or { "(couldn't load)" })
          ctx.preview:highlight({ ft = "markdown" })
        end)
      end,
      confirm = function(picker, it)
        picker:close()
        if it then vim.schedule(function() open_article(it) end) end
      end,
    })
  end
  -- online
  pending = pending + 1
  curl(("%s?action=query&list=search&srsearch=%s&srlimit=50&format=json"):format(API, enc(text)), function(data)
    for _, r in ipairs(data and data.query and data.query.search or {}) do
      items[#items + 1] = { text = r.title .. " " .. strip(r.snippet), title = r.title, snippet = strip(r.snippet):sub(1, 90), source = "online" }
    end
    show()
  end)
  -- offline
  for _, z in ipairs(offline_files()) do
    pending = pending + 1
    vim.system({ "python3", RUNNER .. "/gvwiki.py", "search", z.path, text }, { text = true }, function(r)
      vim.schedule(function()
        local ok, res = pcall(vim.json.decode, r.stdout or "")
        for _, h in ipairs(ok and type(res) == "table" and res or {}) do
          items[#items + 1] = { text = h.title .. " " .. z.name, title = h.title, path = h.path, zim = z.path,
            snippet = "offline · " .. z.name, source = "offline " .. z.name }
        end
        show()
      end)
    end)
  end
end

function M.search(visual)
  local text = vim.fn.expand("<cword>")
  if visual then
    local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    text = table.concat(vim.api.nvim_buf_get_text(0, s[2] - 1, s[3] - 1, e[2] - 1, math.min(e[3], #vim.fn.getline(e[2])), {}), " ")
  end
  Snacks.input({ prompt = "Search Wikipedia", default = text }, function(q)
    if q and vim.trim(q) ~= "" then M.query(q) end
  end)
end

-- :GvWiki install  downloads the offline physics + maths Wikipedia (~650 MB)
function M.install()
  vim.fn.mkdir(ZIMDIR, "p")
  local missing = vim.tbl_filter(function(z) return not vim.uv.fs_stat(ZIMDIR .. "/" .. z.file) end, M.zims)
  if #missing == 0 then return notify("Offline Wikipedia is installed: " .. ZIMDIR) end
  notify("Downloading the offline physics + maths Wikipedia (~650 MB) in the background")
  local cmds = {}
  for _, z in ipairs(missing) do
    cmds[#cmds + 1] = ('curl -fsSL --retry 3 -C - -o "%s/%s.part" "https://download.kiwix.org/zim/wikipedia/%s" && mv "%s/%s.part" "%s/%s"')
      :format(ZIMDIR, z.file, z.file, ZIMDIR, z.file, ZIMDIR, z.file)
  end
  vim.system({ "sh", "-c", table.concat(cmds, " && ") }, {}, function(r)
    vim.schedule(function() notify(r.code == 0 and "Offline Wikipedia ready (Space s w)" or "Offline Wikipedia download failed", r.code == 0 and nil or vim.log.levels.WARN) end)
  end)
end

vim.api.nvim_create_user_command("GvWiki", function(o)
  if o.args == "install" then M.install() else M.query(o.args ~= "" and o.args or vim.fn.expand("<cword>")) end
end, { nargs = "*", desc = "Wikipedia: search, or `install` the offline physics + maths edition" })

return M
