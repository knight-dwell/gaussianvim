-- Run card (like Spyder, as a floating Material card): F5 runs the file you're
-- editing. A card on the right shows the live output (top), the results
-- (middle: errors you can jump to, the plots, and the files the run created or
-- changed) and, at the bottom, a viewer for the plot or file picked in Results.
-- Plots and pictures are drawn as images inside the card (runner/gvplot.py saves
-- the matplotlib figures, kitty draws them) and zoom right there: the mouse
-- wheel or + / -, then drag or hjkl to move around (runner/gvzoom.py draws the
-- zoomed part again, sharp). csv / dat / txt files show as a table you can
-- scroll. Nothing pops up. The card floats over the editor and never squeezes
-- your code; q hides it to a small status pill at the bottom right (click it,
-- or Space r p, to bring it back); Q closes it completely.
--
--   F5 / Space r r   run (saves first)           Ctrl+C / Ctrl+Z / Shift+F5   stop
--   Space r p        show / hide the card        Space r q   close the card
--   Space r ] / [    next / previous plot or file, right from the editor
--   Space r f        go to the viewer            Space r z   zoom in
--   Space r w        plot in a real window       Space r c   clear the plots
--   Space r a        run with arguments          Space r o   type into the program
--   Space r i        Python console with the file loaded
-- In Results: j / k or a click shows that plot or file in the viewer; Enter
-- opens it (a text file in the editor, a plot: go zoom it); o opens it with its
-- app. In the viewer: wheel or + - zoom, 0 fits, hjkl / arrows / drag move
-- (when not zoomed, h l switch), [ ] switch, Enter or w a real window.
-- Everywhere in the card: Tab next pane, q or Esc hide, Q close.
local M = {}
local ns = vim.api.nvim_create_namespace("gv_run")
local ns_view = vim.api.nvim_create_namespace("gv_run_view")
local RUNNER = vim.fn.stdpath("config") .. "/runner"
local PLOT_DIR = vim.fn.stdpath("cache") .. "/run/plots"   -- one folder per run inside
local VIEW_DIR = PLOT_DIR .. "/view"                        -- zoomed views, snapshots of pictures
local ZOOM_STEP, ZOOM_MAX = 1.4, 8
local VIEW_LINES = 2000                                     -- the viewer reads this much of a file
local st = { plots = {}, files = {}, items = {}, rows = {}, args = {}, shown = false, zoom = { z = 1 }, runs = 0 }

local function valid_win(w) return w and vim.api.nvim_win_is_valid(w) end
local function valid_buf(b) return b and vim.api.nvim_buf_is_valid(b) end
local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Run" }) end
local function i3(cmd) if vim.fn.executable("i3-msg") == 1 then vim.system({ "i3-msg", cmd }) end end  -- i3 only
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- how to run each language ----------------------------------------------------

local function python_bin()
  for _, env in ipairs({ vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX }) do
    if env and env ~= "" and vim.fn.executable(env .. "/bin/python") == 1 then return env .. "/bin/python" end
  end
  return vim.fn.executable("python3") == 1 and "python3" or "python"
end

local function compiled(compiler, flags)
  return function(file)
    local exe = vim.fn.stdpath("cache") .. "/run/" .. vim.fn.fnamemodify(file, ":t:r")
    vim.fn.mkdir(vim.fs.dirname(exe), "p")
    return { "bash", "-c", compiler .. " " .. flags .. ' "$1" -o "$2" -lm && exec "$2" "${@:3}"', "_", file, exe }
  end
end

local RUNNERS = {
  python = function(f) return { python_bin(), "-u", f } end,   -- -u: prints show up immediately
  sh = function(f) return { "bash", f } end,
  bash = function(f) return { "bash", f } end,
  zsh = function(f) return { "zsh", f } end,
  julia = function(f) return { "julia", f } end,
  lua = function(f) return { vim.v.progpath, "-l", f } end,
  c = compiled("gcc", "-O2 -Wall"),
  cpp = compiled("g++", "-O2 -Wall -std=c++20"),
  fortran = compiled("gfortran", "-O2 -Wall"),
}

-- files the run created or changed --------------------------------------------

local SKIP_DIRS = { [".git"] = true, ["__pycache__"] = true, ["node_modules"] = true, [".venv"] = true, ["venv"] = true }

local function snapshot(dir)
  local snap, n = {}, 0
  for name, kind in vim.fs.dir(dir, { depth = 2, skip = function(d) return not SKIP_DIRS[vim.fs.basename(d)] end }) do
    if kind == "file" and not vim.fs.basename(name):match("^%.") then
      local s = vim.uv.fs_stat(vim.fs.joinpath(dir, name))
      if s then snap[name] = { mtime = s.mtime.sec * 1e9 + s.mtime.nsec, size = s.size } end
      n = n + 1
      if n > 4000 then break end                -- huge folders: stop looking
    end
  end
  return snap
end

local TEXT_EXT = { txt = 1, csv = 1, tsv = 1, dat = 1, json = 1, log = 1, out = 1, md = 1, py = 1, tex = 1, yaml = 1, yml = 1,
  xyz = 1, cfg = 1, ini = 1, toml = 1, xml = 1, f90 = 1, jl = 1, c = 1, h = 1, cpp = 1, sh = 1, lua = 1, bib = 1, gp = 1, prn = 1 }
local TABLE_EXT = { csv = 1, tsv = 1, dat = 1, txt = 1, xyz = 1, out = 1, prn = 1, [""] = 1 }
local RASTER_EXT = { png = 1, jpg = 1, jpeg = 1, gif = 1, webp = 1, bmp = 1 }   -- zoomable as they are
local VECTOR_EXT = { pdf = 1, svg = 1, eps = 1 }                                -- drawn via ImageMagick
local function ext_of(p) return (p:match("%.([%w]+)$") or ""):lower() end

local function is_binary(path)
  local f = io.open(path, "rb")
  if not f then return false end
  local head = f:read(2048) or ""
  f:close()
  return head:find("%z") ~= nil
end

local function file_kind(path)
  local ext = ext_of(path)
  if RASTER_EXT[ext] or VECTOR_EXT[ext] then return "image" end
  if TEXT_EXT[ext] then return "text" end
  return is_binary(path) and "binary" or "text"
end

local function changed_files()
  if not (st.cwd and st.before) then return {} end
  local out = {}
  for name, info in pairs(snapshot(st.cwd)) do
    local old = st.before[name]
    local full = vim.fs.joinpath(st.cwd, name)
    if full ~= st.file and (not old or old.mtime ~= info.mtime) then
      out[#out + 1] = { name = name, path = full, size = info.size, mtime = info.mtime, new = old == nil, kind = file_kind(full) }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local ICON = { plot = "\u{f0c50}", image = "\u{f02e9}", text = "\u{f0219}", binary = "\u{f0214}" }
local ICON_HL = { plot = "GvUntracked", image = "GvUntracked", text = "GvMenuIcon", binary = "GvMenuDim" }
local function human(n)
  if n < 1024 then return n .. " B" end
  if n < 1024 ^ 2 then return ("%.0f KB"):format(n / 1024) end
  return ("%.1f MB"):format(n / 1024 ^ 2)
end

-- errors in the output ---------------------------------------------------------

-- the terminal breaks long lines at the card width; glue those pieces back together
local function unwrap(lines, width)
  local out, cur = {}, nil
  for _, l in ipairs(lines) do
    cur = cur and (cur .. l) or l
    if vim.fn.strdisplaywidth(l) < width then out[#out + 1] = cur; cur = nil end
  end
  if cur then out[#out + 1] = cur end
  return out
end

local function parse(lines, cwd)
  local frames, msg, compile = {}, nil, {}
  local function abs(p) return p:sub(1, 1) == "/" and p or vim.fs.joinpath(cwd, p) end
  for i, l in ipairs(lines) do
    local f, n = l:match('^%s*File "(.+)", line (%d+)')
    if f and not f:match("site%-packages") and not f:match("/lib/python") and not f:match("^<") then
      frames[#frames + 1] = { file = abs(f), line = tonumber(n), code = vim.trim(lines[i + 1] or "") }
    end
    local cf, cn, cc, kind, cm = l:match("^([^%s:]+):(%d+):(%d+): (%a[%a ]-): (.+)$")
    if cf and (kind:match("error") or kind:match("warning")) then
      compile[#compile + 1] = { file = abs(cf), line = tonumber(cn), col = tonumber(cc), kind = kind, msg = cm }
    end
  end
  if #frames > 0 then
    for i = #lines, 1, -1 do
      local l = vim.trim(lines[i])
      if l ~= "" and not l:match("^%[Process exited") then msg = l; break end
    end
  end
  return msg, vim.list_slice(frames, math.max(1, #frames - 3)), compile
end

-- the card -------------------------------------------------------------------

local function fmt_time(sec)
  if sec < 60 then return ("%.1f s"):format(sec) end
  return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

local function status()
  local name = st.file and vim.fn.fnamemodify(st.file, ":t") or ""
  if st.job then return " ● Running  " .. fmt_time((vim.uv.hrtime() - st.start) / 1e9) .. " ", "GvRunBusy", name end
  if st.stopped then return " ■ Stopped  " .. fmt_time(st.elapsed) .. " ", "GvRunBusy", name end
  if st.code == 0 then return " ✓ Finished  " .. fmt_time(st.elapsed) .. " ", "GvRunOk", name end
  if st.code then return " ✗ Exit " .. st.code .. "  " .. fmt_time(st.elapsed) .. " ", "GvRunFail", name end
  return " F5 runs the file ", "GvRunBusy", ""
end

-- where the card goes: the right side, Output on top, Results below it and,
-- once there is a plot or a file to look at, the viewer under them taking the rest
local function geometry()
  local cols, lines = vim.o.columns, vim.o.lines
  local w = math.min(cols - 8, math.max(56, math.floor(cols * 0.42)))
  local avail = lines - 4                                -- status line, command line, margins
  local geo = { col = cols - w - 3, width = w }
  if #st.items == 0 then
    local ho = math.max(5, math.floor(avail * 0.4) - 2)
    geo.out, geo.res = { row = 0, height = ho }, { row = ho + 2, height = math.max(5, avail - ho - 4) }
  else                                                   -- each float's border takes 2 rows
    local ho = math.max(4, math.floor(avail * 0.22) - 2)
    local hr = math.min(math.max(3, st.res_lines or 3), 10)
    geo.out, geo.res = { row = 0, height = ho }, { row = ho + 2, height = hr }
    geo.plot = { row = ho + hr + 4, height = math.max(6, avail - ho - hr - 6) }
  end
  return geo
end

local function float(cfg, title, footer)
  return vim.tbl_extend("force", {
    relative = "editor", style = "minimal", border = "rounded", zindex = 40, focusable = true,
    title = { { " " .. title .. " ", "FloatTitle" } }, title_pos = "left",
    footer = footer, footer_pos = footer and "right" or nil,
  }, cfg)
end

local function output_buf()
  if valid_buf(st.term_buf) then return st.term_buf end
  if valid_buf(st.idle) then return st.idle end
  st.idle = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(st.idle, 0, -1, false, { "", "  Press F5 to run the file you're editing." })
  vim.bo[st.idle].filetype, vim.bo[st.idle].modifiable = "gvrunterm", false
  M.keys(st.idle)
  return st.idle
end

local function results_buf()
  if valid_buf(st.res_buf) then return st.res_buf end
  st.res_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.res_buf].filetype, vim.bo[st.res_buf].bufhidden = "gvrun", "hide"
  M.keys(st.res_buf)
  -- moving through the list (keys or a click) shows that plot / file in the viewer
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = st.res_buf,
    callback = function()
      local row = st.rows[vim.api.nvim_win_get_cursor(0)[1]]
      if row and row.item and row.item ~= st.sel then M.select(row.item, true) end
    end,
  })
  return st.res_buf
end

local function style(win)
  local wo = vim.wo[win]
  wo.wrap, wo.cursorline, wo.spell = false, false, false
  wo.winhighlight = "Normal:GvMenu,NormalNC:GvMenu,FloatBorder:GvMenuBorder,CursorLine:GvMenuSel"
end

local function update_titles()
  local text, hl, name = status()
  if valid_win(st.out_win) then
    vim.api.nvim_win_set_config(st.out_win, {
      title = { { " \u{f018d} Output" .. (name ~= "" and ("  ·  " .. name) or "") .. " ", "FloatTitle" } }, title_pos = "left",
      footer = st.job and { { text, hl }, { " Ctrl+C stop ", "FloatFooter" } } or { { text, hl } }, footer_pos = "right",
    })
  end
  if valid_win(st.pill) then
    local label = text .. (#st.files > 0 and ("· " .. #st.files .. " file" .. (#st.files > 1 and "s " or " ")) or "")
      .. (#st.plots > 0 and ("· " .. #st.plots .. " plot" .. (#st.plots > 1 and "s " or " ")) or "")
    vim.bo[st.pill_buf].modifiable = true
    vim.api.nvim_buf_set_lines(st.pill_buf, 0, -1, false, { label })
    vim.bo[st.pill_buf].modifiable = false
    vim.wo[st.pill].winhighlight = "Normal:" .. hl
    local w = vim.fn.strdisplaywidth(label)
    vim.api.nvim_win_set_config(st.pill, { relative = "editor", row = vim.o.lines - 3, col = vim.o.columns - w - 2, width = w, height = 1 })
  end
end

-- the small status pill shown while the card is hidden (click it to open the card)
local function show_pill()
  if not st.file then return end
  if not valid_buf(st.pill_buf) then
    st.pill_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[st.pill_buf].filetype = "gvrunpill"
  end
  if not valid_win(st.pill) then
    st.pill = vim.api.nvim_open_win(st.pill_buf, false, { relative = "editor", row = vim.o.lines - 3, col = vim.o.columns - 20,
      width = 18, height = 1, style = "minimal", zindex = 45, focusable = true })
  end
  update_titles()
end

local function hide_pill()
  if valid_win(st.pill) then vim.api.nvim_win_close(st.pill, true) end
  st.pill = nil
end

-- plots and files to look at ---------------------------------------------------
-- runner/gvplot.py saves each figure the program shows as
-- <run dir>/plot-NNN-VVVVV.png (+ .pickle for zoom and the real window). A
-- redraw of the same figure gets a new VVVVV, so the newest file per NNN is the
-- plot to show. Every run gets its own folder: the image library remembers
-- pictures by path, so a re-run must never reuse an old plot's path.

local function plot_files()
  local by = {}
  if st.run_dir and vim.uv.fs_stat(st.run_dir) then
    for name, kind in vim.fs.dir(st.run_dir) do
      local n, v = name:match("^plot%-(%d+)%-(%d+)%.png$")
      if kind == "file" and n then
        n, v = tonumber(n), tonumber(v)
        if not by[n] or by[n].v < v then by[n] = { n = n, v = v, png = vim.fs.joinpath(st.run_dir, name) } end
      end
    end
  end
  local list = vim.tbl_values(by)
  table.sort(list, function(a, b) return a.n < b.n end)
  return list
end

-- the list the viewer steps through: plots first, then the files; keeps the
-- picked one picked
local function rebuild_items()
  local cur = st.items[st.sel or 0]
  local keep = cur and cur.key
  local items = {}
  for _, p in ipairs(st.plots) do
    items[#items + 1] = { kind = "plot", key = "plot:" .. p.n, png = p.png, n = p.n, label = "Plot " .. p.n }
  end
  for _, f in ipairs(st.files) do
    items[#items + 1] = { kind = f.kind, key = "file:" .. f.path, path = f.path, label = f.name, size = f.size, mtime = f.mtime, new = f.new }
  end
  st.items, st.sel = items, nil
  for i, it in ipairs(items) do
    if it.key == keep then st.sel = i end
  end
  if not st.sel and #items > 0 then st.sel = 1 end
  local now = st.items[st.sel or 0]
  if not (now and st.zoom.key == now.key) then st.zoom = { z = 1, cx = 0.5, cy = 0.5, key = now and now.key } end
end

-- new plots or redrawn ones: show the newest
local function check_plots()
  local list, changed = plot_files(), false
  for i = 1, math.max(#list, #st.plots) do
    if (list[i] and list[i].png) ~= (st.plots[i] and st.plots[i].png) then changed = true end
  end
  if not changed then return end
  local more = #list > #st.plots
  st.plots = list
  rebuild_items()
  if more then st.sel = #list; st.zoom = { z = 1, cx = 0.5, cy = 0.5, key = st.items[#list].key } end
  M.render()
end

local function plot_buf()
  if valid_buf(st.plot_buf) then return st.plot_buf end
  st.plot_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.plot_buf].filetype, vim.bo[st.plot_buf].bufhidden = "gvrunplot", "hide"
  M.keys(st.plot_buf)
  return st.plot_buf
end

local function view_buf()
  if valid_buf(st.view_buf) then return st.view_buf end
  st.view_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.view_buf].filetype, vim.bo[st.view_buf].bufhidden = "gvrunview", "hide"
  M.keys(st.view_buf)
  -- the row under the cursor is highlighted only while you are in the viewer
  vim.api.nvim_create_autocmd({ "BufEnter", "BufLeave" }, {
    buffer = st.view_buf,
    callback = function(ev) vim.wo.cursorline = ev.event == "BufEnter" end,
  })
  return st.view_buf
end

local function forget_image()
  for _, p in ipairs({ st.placement, st.old_placement }) do pcall(p.close, p) end
  st.placement, st.old_placement, st.drawn = nil, nil, nil
end

-- the image library's own cache of our pictures (they are thrown away anyway)
local function snacks_cache() return (Snacks and Snacks.image and Snacks.image.config and Snacks.image.config.cache) or nil end
local function forget_cached(pattern)
  local dir = snacks_cache()
  if not dir then return end
  for _, f in ipairs(vim.fn.glob(dir .. "/" .. pattern, false, true)) do os.remove(f) end
end
local function drop_file(path)
  if not path then return end
  os.remove(path)
  forget_cached("*-" .. vim.fn.fnamemodify(path, ":t:r"):gsub("[^%w%.]+", "-") .. ".*")
end

-- pictures the run wrote are shown from a copy named after their time, so a
-- re-run that rewrites fig.png never shows the old picture
local function picture_src(it)
  if it.kind == "plot" then return it.png end
  local ext = ext_of(it.path)
  local copy = ("%s/file-%s-%.0f.%s"):format(VIEW_DIR, vim.fn.sha256(it.path):sub(1, 10), it.mtime or 0, ext)
  if not vim.uv.fs_stat(copy) then
    vim.fn.mkdir(VIEW_DIR, "p")
    if not vim.uv.fs_copyfile(it.path, copy) then return it.path end
  end
  return copy
end

local dims = {}
local function img_dims(src)
  if dims[src] == nil then
    local ok, d = pcall(Snacks.image.util.dim, src)          -- PNG: read from the header
    if not ok then
      local r = vim.system({ "magick", "identify", "-format", "%w %h", src .. "[0]" }, { text = true }):wait(5000)
      local w, h = (r.stdout or ""):match("(%d+) (%d+)")
      d = w and { width = tonumber(w), height = tonumber(h) } or false
    end
    dims[src] = d
  end
  return dims[src] or nil
end

local function cell_px()
  local t = Snacks.image.terminal.size()
  return t.cell_width, t.cell_height
end

-- the viewer's drawing area in cells (the last row stays free)
local function view_cells()
  return vim.api.nvim_win_get_width(st.plot_win), math.max(1, vim.api.nvim_win_get_height(st.plot_win) - 1)
end

-- width in cells of a picture fitted into w x h cells (to centre it)
local function fit_width(src, w, h)
  local d = img_dims(src)
  if not d then return w end
  local cw, ch = cell_px()
  local s = math.min(w * cw / d.width, h * ch / d.height)
  return clamp(math.floor(d.width * s / cw + 0.5), 1, w)
end

-- text files: a table for csv / dat / txt columns, the text otherwise ------------

local function is_num(s)
  if tonumber(s) then return true end
  s = s:lower()
  return s == "nan" or s == "inf" or s == "-inf" or s == "+inf" or tonumber((s:gsub("d", "e"))) ~= nil
end

local function split_row(line, sep)
  if sep == " " then return vim.split(vim.trim(line), "%s+", { trimempty = true }) end
  if not line:find('"', 1, true) then
    local cells = vim.split(line, sep, { plain = true })
    for i, c in ipairs(cells) do cells[i] = vim.trim(c) end
    return cells
  end
  local cells, cur, q, i, n = {}, {}, false, 1, #line           -- "quoted, cells"
  while i <= n do
    local c = line:sub(i, i)
    if q then
      if c == '"' and line:sub(i + 1, i + 1) == '"' then cur[#cur + 1] = '"'; i = i + 1
      elseif c == '"' then q = false
      else cur[#cur + 1] = c end
    elseif c == '"' then q = true
    elseif c == sep then cells[#cells + 1] = vim.trim(table.concat(cur)); cur = {}
    else cur[#cur + 1] = c end
    i = i + 1
  end
  cells[#cells + 1] = vim.trim(table.concat(cur))
  return cells
end

local function read_head(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local lines, more = {}, false
  for l in f:lines() do
    if #lines >= VIEW_LINES then more = true; break end
    l = l:gsub("\r$", "")
    if #l > 1000 then l = l:sub(1, 1000) .. " …" end
    lines[#lines + 1] = l
  end
  f:close()
  return lines, more
end

local function is_comment(l) return l:match("^%s*[#%%!]") or l:match("^%s*//") end

-- lines + highlights for a file that holds columns of numbers; nil if it doesn't
local function table_view(lines, ext, more)
  local comments, data = {}, {}
  for _, l in ipairs(lines) do
    if l:match("^%s*$") then                             -- skip blank lines
    elseif is_comment(l) then
      if #data == 0 then comments[#comments + 1] = l end
    else data[#data + 1] = l end
  end
  if #data == 0 then return nil end
  local sample = vim.list_slice(data, 1, 30)
  local function all_have(ch)
    for _, l in ipairs(sample) do if not l:find(ch, 1, true) then return false end end
    return true
  end
  local sep = ext == "tsv" and "\t" or ext == "csv" and (all_have(";") and not all_have(",") and ";" or ",")
    or (all_have(",") and ",") or (all_have("\t") and "\t") or (all_have(";") and ";") or " "
  local rows, counts = {}, {}
  for i, l in ipairs(data) do
    rows[i] = split_row(l, sep)
    counts[#rows[i]] = (counts[#rows[i]] or 0) + 1
  end
  local ncols, best = 0, 0
  for c, k in pairs(counts) do
    if k > best or (k == best and c > ncols) then ncols, best = c, k end
  end
  if ncols < 2 or best < 0.8 * #rows then return nil end
  local function numbers(r)
    local k = 0
    for _, c in ipairs(r) do if is_num(c) then k = k + 1 end end
    return k
  end
  local header
  if #rows > 1 and numbers(rows[1]) < #rows[1] and numbers(rows[2]) > numbers(rows[1]) then header = table.remove(rows, 1) end
  if sep == " " then                                   -- whitespace columns: only if mostly numbers
    local cells, nums = 0, 0
    for i = 1, math.min(#rows, 50) do cells = cells + #rows[i]; nums = nums + numbers(rows[i]) end
    if nums < 0.6 * cells then return nil end
  end
  if not header and #comments > 0 then                 -- numpy.savetxt: names in the last # line
    local cells = split_row((comments[#comments]:gsub("^%s*[#%%!/]+%s*", "")), sep)
    if #cells == ncols then header = cells; table.remove(comments) end
  end

  -- each column of numbers gets one format, so the decimal points line up:
  -- whole numbers as they are, plain decimals with as many places as written
  -- (at most 8), long or 1e-5 style numbers as %.6f or %.6e
  local function to_num(v) return tonumber(v) or tonumber((v:gsub("[dD]", "e"))) end
  local fmts = {}
  for c = 1, ncols do
    local nums, maxabs, minabs, dec, sci, int, cells = 0, 0, math.huge, 0, false, true, 0
    for _, r in ipairs(rows) do
      local v = r[c]
      if v and v ~= "" then
        cells = cells + 1
        local n = to_num(v)
        if n then
          nums = nums + 1
          local a = math.abs(n)
          if a == a and a ~= math.huge then
            maxabs = math.max(maxabs, a)
            if a > 0 then minabs = math.min(minabs, a) end
            if n ~= math.floor(n) then int = false end
          end
          if v:find("[eEdD]") or #v > 12 then sci = true
          else dec = math.max(dec, #(v:match("%.(%d+)$") or "")) end
        end
      end
    end
    if cells > 0 and nums >= 0.8 * cells then
      local f
      if int and maxabs < 1e15 then f = "%.0f"
      elseif not sci then f = "%." .. math.min(dec, 8) .. "f"
      elseif maxabs < 1e5 and minabs >= 1e-3 then f = "%.6f"
      else f = "%.6e" end
      fmts[c] = function(v)
        local n = to_num(v)
        if not n or n ~= n or math.abs(n) == math.huge then return v end
        return (f):format(n)
      end
    end
  end
  local MAXW = 22
  local function cell(c, v, is_head)
    v = v or ""
    if fmts[c] and not is_head then v = fmts[c](v) end
    if vim.api.nvim_strwidth(v) > MAXW then return vim.fn.strcharpart(v, 0, MAXW - 1) .. "…" end
    return v
  end
  local widths = {}
  if header then
    for c = 1, ncols do widths[c] = vim.api.nvim_strwidth(cell(c, header[c], true)) end
  end
  for _, r in ipairs(rows) do
    for c = 1, ncols do widths[c] = math.max(widths[c] or 1, vim.api.nvim_strwidth(cell(c, r[c]))) end
  end
  local function join(r, is_head)
    local parts = {}
    for c = 1, ncols do
      local v = cell(c, r[c], is_head)
      local pad = string.rep(" ", widths[c] - vim.api.nvim_strwidth(v))
      parts[c] = fmts[c] and (pad .. v) or (v .. pad)          -- numbers to the right
    end
    return table.concat(parts, "  ")
  end
  local gut = #tostring(#rows)
  local lead = string.rep(" ", gut + 3)
  local out, hls = {}, {}
  local seps = { [","] = "comma", ["\t"] = "tab", [";"] = "semicolon", [" "] = "space" }
  out[1] = (" %d rows × %d columns · %s-separated%s"):format(#rows, ncols, seps[sep], more and (" · first " .. VIEW_LINES .. " lines") or "")
  hls[#hls + 1] = { 0, 0, -1, "GvMenuDim" }
  for _, c in ipairs(comments) do
    out[#out + 1] = "  " .. c
    hls[#hls + 1] = { #out - 1, 0, -1, "Comment" }
  end
  if header then
    out[#out + 1] = lead .. join(header, true)
    hls[#hls + 1] = { #out - 1, #lead, -1, "GvSection" }
    out[#out + 1] = lead .. string.rep("─", vim.api.nvim_strwidth(join(header, true)))
    hls[#hls + 1] = { #out - 1, 0, -1, "GvMenuDim" }
  end
  for i, r in ipairs(rows) do
    local num = (" %" .. gut .. "d  "):format(i)
    out[#out + 1] = num .. join(r)
    hls[#hls + 1] = { #out - 1, 0, #num, "GvMenuDim" }
  end
  return out, hls
end

local function show_text(it)
  local buf = view_buf()
  local out, hls
  if it.kind == "binary" then
    out = { "", "  Binary file · " .. human(it.size or 0), "", "  o opens it with its app" }
    hls = { { 1, 0, -1, "GvMenuDim" }, { 3, 0, -1, "GvPlaceholder" } }
  else
    local lines, more = read_head(it.path)
    if not lines then
      out, hls = { "", "  Can't read this file." }, {}
    else
      if TABLE_EXT[ext_of(it.path)] then out, hls = table_view(lines, ext_of(it.path), more) end
      if not out then                                    -- plain text
        out, hls = lines, {}
        for i, l in ipairs(lines) do
          if is_comment(l) then hls[#hls + 1] = { i - 1, 0, -1, "Comment" } end
        end
        if #out == 0 then out = { "", "  (empty file)" } end
        if more then
          out[#out + 1] = (" … first %d lines · Enter opens the whole file"):format(VIEW_LINES)
          hls[#hls + 1] = { #out - 1, 0, -1, "GvPlaceholder" }
        end
      end
    end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns_view, 0, -1)
  for _, h in ipairs(hls) do
    local len = #(out[h[1] + 1] or "")
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_view, h[1], math.min(h[2], len), { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4] })
  end
  if vim.api.nvim_win_get_buf(st.plot_win) ~= buf then
    vim.api.nvim_win_set_buf(st.plot_win, buf)
    style(st.plot_win)
  end
  vim.wo[st.plot_win].cursorline = vim.api.nvim_get_current_win() == st.plot_win
  pcall(vim.api.nvim_win_set_cursor, st.plot_win, { 1, 0 })
end

-- the viewer: the picked plot / picture / file -----------------------------------

local function zoomable(it) return it and (it.kind == "plot" or it.kind == "image") end

local function view_labels(it)
  local n, zoomed = #st.items, zoomable(it) and st.zoom.z > 1.001
  local title = " " .. ICON[it.kind] .. " " .. it.label .. (zoomed and ("  " .. ("%.1f"):format(st.zoom.z) .. "×") or "")
    .. (n > 1 and ("  ·  " .. st.sel .. "/" .. n) or "") .. " "
  local footer
  if zoomed then footer = " hjkl / drag move · + - zoom · 0 fit "
  elseif zoomable(it) then footer = " wheel / + zoom" .. (n > 1 and " · [ ] next" or "") .. (it.kind == "plot" and " · w window " or " · o open ")
  elseif it.kind == "text" then footer = (n > 1 and " [ ] next ·" or "") .. " Enter edit · o app "
  else footer = (n > 1 and " [ ] next ·" or "") .. " o open with its app " end
  return title, footer
end

local function draw_view()
  local it = st.items[st.sel or 0]
  if not (it and valid_win(st.plot_win)) then return end
  local title, footer = view_labels(it)
  vim.api.nvim_win_set_config(st.plot_win, {
    title = { { title, "FloatTitle" } }, title_pos = "left",
    footer = { { footer, "FloatFooter" } }, footer_pos = "right",
  })
  local w, h = view_cells()
  local z = st.zoom
  local zoomed = zoomable(it) and z.z > 1.001 and z.out
  local src = zoomed and z.out or (zoomable(it) and picture_src(it)) or it.path
  local key = table.concat({ it.key, src, w, h, it.size or "" }, "|")
  if st.drawn == key then return end
  if not zoomable(it) then
    forget_image()
    st.drawn = key
    return show_text(it)
  end
  st.drawn = key
  local buf = plot_buf()
  if vim.api.nvim_win_get_buf(st.plot_win) ~= buf then
    forget_image()
    st.drawn = key
    vim.api.nvim_win_set_buf(st.plot_win, buf)
    style(st.plot_win)
  end
  local ok = pcall(function()
    if not Snacks.image.supports_terminal() then error("no kitty graphics") end
    local mw, mh = w, h
    if zoomed then                                  -- exactly the size gvzoom.py drew it
      local cw, ch = cell_px()
      mw, mh = clamp(math.floor(z.w / cw + 0.5), 1, w), clamp(math.floor(z.h / ch + 0.5), 1, h)
    end
    local fw = zoomed and mw or fit_width(src, w, h)
    local off = math.max(0, math.floor((w - fw) / 2))
    if vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] ~= "" or vim.api.nvim_buf_line_count(buf) ~= 1 then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      vim.bo[buf].modifiable = false
    end
    -- the old picture stays until the new one is on screen: no blank flash
    if st.old_placement then pcall(st.old_placement.close, st.old_placement) end
    local old = st.placement
    st.old_placement = old
    st.placement = Snacks.image.placement.new(buf, src, {
      pos = { 1, off }, inline = true, max_width = mw, max_height = mh,
      on_update = function()
        if old then pcall(old.close, old); if st.old_placement == old then st.old_placement = nil end; old = nil end
      end,
    })
  end)
  if not ok then                                  -- e.g. over ssh: say what to do instead
    forget_image()
    st.drawn = key
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  Can't draw images in this terminal.", "  Enter opens the plot in a window, o in its app." })
    vim.bo[buf].modifiable = false
  end
end

-- zoom inside the viewer -------------------------------------------------------
-- st.zoom = { z, cx, cy, key, out, w, h }: z = 1 is the whole picture fitted in
-- the viewer; (cx, cy) is the point of the picture (0..1) in the middle of the
-- view. runner/gvzoom.py (started on the first zoom, stopped when the card
-- hides) draws the visible part at that zoom; requests made while it is busy
-- are merged, so wheel spins and drags stay smooth.

local zoomer = { id = 0, partial = "" }

-- the picture to zoom (and the pickled figure, for plots)
local function zoom_src(it)
  if it.kind == "plot" then
    local pickle = it.png:gsub("%.png$", ".pickle")
    return it.png, vim.uv.fs_stat(pickle) and pickle or nil
  end
  if RASTER_EXT[ext_of(it.path)] then return picture_src(it) end
  local img = st.placement and st.placement.img      -- PDF / SVG: the PNG ImageMagick made of it
  if img and img.file and img.file:match("%.png$") and vim.uv.fs_stat(img.file) then return img.file end
end

-- the picture's size in viewer pixels at zoom z, and the viewer's size in pixels
local function zoom_geo(d, z)
  local w, h = view_cells()
  local cw, ch = cell_px()
  local vw, vh = w * cw, h * ch
  local s = math.min(vw / d.width, vh / d.height) * z
  return d.width * s, d.height * s, vw, vh
end

local function keep_inside(zs, zw, zh, vw, vh)
  local hx, hy = math.min(vw, zw) / zw / 2, math.min(vh, zh) / zh / 2
  zs.cx, zs.cy = clamp(zs.cx, hx, 1 - hx), clamp(zs.cy, hy, 1 - hy)
end

local function zoomer_stop()
  if zoomer.job then pcall(vim.fn.jobstop, zoomer.job) end
  zoomer.job, zoomer.busy, zoomer.pending, zoomer.want = nil, false, nil, nil
end

local zoomer_send

-- a zoomed view is ready: show it once kitty has it, then drop the last one
local function on_answer(ans)
  zoomer.busy = false
  local it = st.items[st.sel or 0]
  local current = ans.id == zoomer.want and it and it.key == zoomer.want_key and st.zoom.z > 1.001
  if current and ans.error then
    notify("Can't zoom this one (" .. ans.error .. "); o opens it in its app", vim.log.levels.WARN)
    M.zoom_fit()
  elseif current then
    local function show()
      if st.zoom.out ~= ans.out then drop_file(ans.out); return end
      draw_view()
    end
    local old = st.zoom.out
    st.zoom.out, st.zoom.w, st.zoom.h, st.zoom.cx, st.zoom.cy = ans.out, ans.w, ans.h, ans.cx, ans.cy
    if old then vim.defer_fn(function() drop_file(old) end, 2000) end
    -- let the image library load it first, so the old view stays until then
    local ok, img = pcall(function() return Snacks.image.supports_terminal() and Snacks.image.image.new(ans.out) end)
    if not (ok and img) then show() else
      local tries = 0
      local function poll()
        tries = tries + 1
        if (img:ready() and img.sent) or img:failed() or tries > 150 then return show() end
        vim.defer_fn(poll, 15)
      end
      poll()
    end
  elseif ans.out then
    drop_file(ans.out)
  end
  zoomer_send()
end

zoomer_send = function()
  local req = zoomer.pending
  if not req or zoomer.busy then return end
  if not zoomer.job then
    zoomer.partial = ""
    zoomer.job = vim.fn.jobstart({ python_bin(), "-u", RUNNER .. "/gvzoom.py" }, {
      on_stdout = function(_, data)
        data[1] = zoomer.partial .. data[1]
        zoomer.partial = table.remove(data)
        for _, line in ipairs(data) do
          local ok, ans = pcall(vim.json.decode, line)
          if ok and type(ans) == "table" then vim.schedule(function() on_answer(ans) end) end
        end
      end,
      on_stderr = function(_, data) zoomer.err = table.concat(data, "\n") end,
      on_exit = function(job)
        if zoomer.job == job then zoomer.job, zoomer.busy = nil, false end
      end,
    })
    if zoomer.job <= 0 then
      zoomer.job = nil
      return notify("Can't start the zoom helper (" .. python_bin() .. ")", vim.log.levels.ERROR)
    end
  end
  zoomer.pending, zoomer.busy = nil, true
  vim.fn.chansend(zoomer.job, vim.json.encode(req) .. "\n")
end

local function request(it, src, pickle, vw, vh)
  zoomer.id = zoomer.id + 1
  vim.fn.mkdir(VIEW_DIR, "p")
  zoomer.want, zoomer.want_key = zoomer.id, it.key
  zoomer.pending = {
    id = zoomer.id, png = src, pickle = pickle, z = st.zoom.z, cx = st.zoom.cx, cy = st.zoom.cy,
    vw = math.floor(vw), vh = math.floor(vh),
    out = ("%s/zoom-%d-%d.png"):format(VIEW_DIR, vim.fn.getpid(), zoomer.id),
  }
  zoomer_send()
  local title = view_labels(it)                     -- the new zoom level right away
  pcall(vim.api.nvim_win_set_config, st.plot_win, { title = { { title, "FloatTitle" } }, title_pos = "left" })
end

-- where the mouse is in the viewer, in pixels from its top left corner
-- (getmousepos() counts the border: the first cell inside is row 2, column 2)
local function mouse_px(m)
  if not (m and m.winid == st.plot_win and m.winrow > 1 and m.wincol > 1) then return nil end
  local cw, ch = cell_px()
  return (m.wincol - 1.5) * cw, (m.winrow - 1.5) * ch
end

-- zoom to z, keeping the point under the mouse (or the middle) where it is
function M.zoom_to(z, mouse)
  local it = st.items[st.sel or 0]
  if not zoomable(it) then return notify("Pick a plot or a picture to zoom") end
  if not valid_win(st.plot_win) then return end
  local src, pickle = zoom_src(it)
  local d = src and img_dims(src)
  if not d then return notify("Can't zoom this one; o opens it in its app", vim.log.levels.WARN) end
  local zs = st.zoom
  z = math.min(ZOOM_MAX, z)
  if math.abs(z - zs.z) < 1e-3 then return end            -- already there (fit, or the most zoom)
  if z <= 1.001 then return M.zoom_fit() end
  local zw, zh, vw, vh = zoom_geo(d, zs.z)
  local oh = math.min(vh, zh)
  local ax, ay = mouse_px(mouse)
  ax, ay = ax or vw / 2, ay or oh / 2
  local px = clamp(zs.cx + (ax - vw / 2) / zw, 0, 1)   -- the picture's point under the mouse
  local py = clamp(zs.cy + (ay - oh / 2) / zh, 0, 1)
  local nzw, nzh = zoom_geo(d, z)
  zs.z = z
  zs.cx = px - (ax - vw / 2) / nzw
  zs.cy = py - (ay - math.min(vh, nzh) / 2) / nzh
  keep_inside(zs, nzw, nzh, vw, vh)
  request(it, src, pickle, vw, vh)
end

function M.zoom_in(mouse) M.zoom_to(st.zoom.z * ZOOM_STEP, mouse) end
function M.zoom_out(mouse) M.zoom_to(st.zoom.z / ZOOM_STEP, mouse) end

-- back to the whole picture
function M.zoom_fit()
  local it = st.items[st.sel or 0]
  local old = st.zoom.out
  st.zoom = { z = 1, cx = 0.5, cy = 0.5, key = it and it.key }
  zoomer.want, zoomer.pending = nil, nil
  st.drawn = nil
  draw_view()
  if old then vim.defer_fn(function() drop_file(old) end, 2000) end
end

-- move the zoomed view by (dx, dy) views
function M.pan(dx, dy)
  local it = st.items[st.sel or 0]
  if not (zoomable(it) and st.zoom.z > 1.001) then return end
  local src, pickle = zoom_src(it)
  local d = src and img_dims(src)
  if not d then return end
  local zw, zh, vw, vh = zoom_geo(d, st.zoom.z)
  local zs = st.zoom
  local cx, cy = zs.cx, zs.cy
  zs.cx = zs.cx + dx * math.min(vw, zw) / zw
  zs.cy = zs.cy + dy * math.min(vh, zh) / zh
  keep_inside(zs, zw, zh, vw, vh)
  if zs.cx ~= cx or zs.cy ~= cy then request(it, src, pickle, vw, vh) end
end

-- drag the zoomed picture with the mouse
function M.drag(phase, m)
  m = m or vim.fn.getmousepos()
  if phase == "release" then st.drag = nil; return end
  if m.winid ~= st.plot_win or st.zoom.z <= 1.001 then return end
  if phase == "press" or not st.drag then
    st.drag = { col = m.wincol, row = m.winrow, cx = st.zoom.cx, cy = st.zoom.cy }
    return
  end
  local it = st.items[st.sel or 0]
  local src, pickle = zoom_src(it)
  local d = src and img_dims(src)
  if not d then return end
  local zw, zh, vw, vh = zoom_geo(d, st.zoom.z)
  local cw, ch = cell_px()
  local zs = st.zoom
  zs.cx = st.drag.cx - (m.wincol - st.drag.col) * cw / zw
  zs.cy = st.drag.cy - (m.winrow - st.drag.row) * ch / zh
  keep_inside(zs, zw, zh, vw, vh)
  request(it, src, pickle, vw, vh)
end

-- open / move the card's floats to match geometry()
local function layout()
  if not st.shown then return end
  local geo = geometry()
  if vim.deep_equal(geo, st.geo) and valid_win(st.out_win) and valid_win(st.res_win)
    and (geo.plot == nil) == not valid_win(st.plot_win) then return end
  st.geo = geo
  local function cfg(part) return { relative = "editor", row = part.row, col = geo.col, width = geo.width, height = part.height } end
  if valid_win(st.out_win) then vim.api.nvim_win_set_config(st.out_win, cfg(geo.out))
  else st.out_win = vim.api.nvim_open_win(output_buf(), false, float(cfg(geo.out), "\u{f018d} Output")); style(st.out_win) end
  if valid_win(st.res_win) then vim.api.nvim_win_set_config(st.res_win, cfg(geo.res))
  else
    st.res_win = vim.api.nvim_open_win(results_buf(), false, float(cfg(geo.res), "\u{f012a} Results",
      { { " Enter open · [ ] next · Tab · q hide ", "FloatFooter" } }))
    style(st.res_win)
  end
  if geo.plot then
    if valid_win(st.plot_win) then vim.api.nvim_win_set_config(st.plot_win, cfg(geo.plot))
    else st.plot_win = vim.api.nvim_open_win(plot_buf(), false, float(cfg(geo.plot), "\u{f0c50} Plot")); style(st.plot_win) end
    st.drawn = nil                                -- new size: draw again
    if st.zoom.z > 1.001 then st.zoom = { z = 1, cx = 0.5, cy = 0.5, key = st.zoom.key } end
  elseif valid_win(st.plot_win) then
    forget_image()
    vim.api.nvim_win_close(st.plot_win, true)
    st.plot_win = nil
  end
end

-- results text, then the card's layout and the viewer
function M.render()
  local buf = results_buf()
  local lines, hls, rows, item_row = {}, {}, {}, {}
  local function add(text, row, spans)
    lines[#lines + 1] = text
    rows[#lines] = row
    for _, s in ipairs(spans or {}) do hls[#hls + 1] = { #lines - 1, s[1], s[2], s[3] } end
  end
  local text, hl, name = status()
  if #st.items == 0 or st.error then
    add(" " .. text .. "  " .. name, nil, { { 1, 1 + #text, hl } })
    add("", nil)
  end
  if st.error then
    add("  " .. st.error, nil, { { 0, -1, "GvDeleted" } })
    for _, f in ipairs(st.frames or {}) do
      local where = ("    → %s:%d"):format(vim.fn.fnamemodify(f.file, ":t"), f.line)
      add(where .. "   " .. (f.code or ""), f, { { 4, #where, "GvMenuIcon" }, { #where, -1, "Comment" } })
    end
    add("", nil)
  end
  for _, e in ipairs(st.compile or {}) do
    local where = ("  %s:%d:%d"):format(vim.fn.fnamemodify(e.file, ":t"), e.line, e.col or 0)
    add(where .. "  " .. e.kind .. ": " .. e.msg, e, { { 0, #where, "GvMenuIcon" }, { #where, -1, e.kind:match("error") and "GvDeleted" or "GvModified" } })
  end
  if st.compile and #st.compile > 0 then add("", nil) end
  local w = valid_win(st.res_win) and vim.api.nvim_win_get_width(st.res_win) or 60
  local function section(title, count)
    local head = " " .. title .. " "
    add(head .. " " .. count .. " ", nil, { { 0, #head, "GvSection" }, { #head, -1, "GvBadge" } })
  end
  local function item_line(i, it, right)
    local icon = ICON[it.kind]
    local left = "   " .. icon .. "  " .. it.label
    local l = left .. (right and (string.rep(" ", math.max(2, w - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right) - 2)) .. right) or "")
    add(l, { item = i, key = it.key }, { { 3, 3 + #icon, ICON_HL[it.kind] }, right and { #l - #right, -1, "GvMenuDim" } or nil })
    item_row[i] = #lines
  end
  if #st.plots > 0 then
    section("PLOTS", #st.plots)
    for i, it in ipairs(st.items) do
      if it.kind == "plot" then item_line(i, it) end
    end
    add("", nil)
  end
  if #st.files > 0 then
    section("FILES", #st.files)
    for i, it in ipairs(st.items) do
      if it.kind ~= "plot" then item_line(i, it, human(it.size) .. (it.new and "  new" or "  updated")) end
    end
  end
  if #st.items == 0 and not st.job and not st.error and not (st.compile and #st.compile > 0) then
    add("  Plots and files the run creates appear here.", nil, { { 0, -1, "GvPlaceholder" } })
  end
  -- the cursor stays on the same plot / file when the list changes
  local cur_key
  if valid_win(st.res_win) then
    local r = st.rows[vim.api.nvim_win_get_cursor(st.res_win)[1]]
    cur_key = r and r.key
  end
  st.rows, st.res_lines, st.item_row = rows, #lines, item_row
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    local len = #lines[h[1] + 1]
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], math.min(h[2], len), { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4] })
  end
  if st.sel and item_row[st.sel] then             -- the plot / file in the viewer
    vim.api.nvim_buf_set_extmark(buf, ns, item_row[st.sel] - 1, 0, { line_hl_group = "GvMenuSel", priority = 50 })
  end
  layout()
  if cur_key and valid_win(st.res_win) then
    for l, r in pairs(rows) do
      if r.key == cur_key then pcall(vim.api.nvim_win_set_cursor, st.res_win, { l, 0 }) end
    end
  end
  update_titles()
  draw_view()
end

-- show item i in the viewer (from_list: picked in Results, the cursor is there already)
function M.select(i, from_list)
  local it = st.items[i]
  if not it then return end
  st.sel = i
  if st.zoom.key ~= it.key then
    local old = st.zoom.out
    st.zoom = { z = 1, cx = 0.5, cy = 0.5, key = it.key }
    zoomer.want, zoomer.pending = nil, nil
    if old then vim.defer_fn(function() drop_file(old) end, 2000) end
  end
  M.render()
  if not from_list and valid_win(st.res_win) and st.item_row[i] then
    pcall(vim.api.nvim_win_set_cursor, st.res_win, { st.item_row[i], 0 })
  end
end

-- next / previous plot or file
function M.next_item(step)
  local n = #st.items
  if n == 0 then return notify("No plots or files yet") end
  if not st.shown then M.show() end
  M.select(((st.sel or 1) - 1 + step) % n + 1)
end
function M.next_plot(step) M.next_item(step) end   -- old name

-- the plot as a real matplotlib window (zoom / pan / save toolbar), from its
-- pickled copy; the image viewer if that can't be done
function M.window()
  local it = st.items[st.sel or 0]
  if not it then return notify("No plot yet") end
  if it.kind ~= "plot" then return vim.ui.open(it.path) end
  local pickle = it.png:gsub("%.png$", ".pickle")
  local title = ("GvPlot · %s · plot %d"):format(vim.fn.fnamemodify(st.file or "", ":t"), it.n)
  if not vim.uv.fs_stat(pickle) then return vim.ui.open(it.png) end
  vim.system({ python_bin(), RUNNER .. "/gvview.py", pickle, title }, {}, function(r)
    if r.code ~= 0 then vim.schedule(function() vim.ui.open(it.png) end) end
  end)
end

-- the plot / file with its own app (image viewer, LibreOffice, ...)
function M.open_app()
  local i = st.sel
  if vim.api.nvim_get_current_buf() == st.res_buf then
    local row = st.rows[vim.api.nvim_win_get_cursor(0)[1]]
    i = row and row.item or i
  end
  local it = st.items[i or 0]
  if not it then return notify("No plot or file here") end
  vim.ui.open(it.png or it.path)
end

local function open_in_editor(path, line, col)
  vim.api.nvim_set_current_win(require("gv.git").edit_window())
  vim.cmd.edit(vim.fn.fnameescape(path))
  if line then
    pcall(vim.api.nvim_win_set_cursor, 0, { line, math.max(0, (col or 1) - 1) })
    vim.cmd("normal! zz")
  end
end

-- Enter on a plot / file: a text file in the editor; a picture: go to the
-- viewer (from Results) or a real window (from the viewer)
function M.open_item(i, from)
  local it = st.items[i or 0]
  if not it then return end
  if it.kind == "text" then return open_in_editor(it.path) end
  if it.kind == "binary" then return vim.ui.open(it.path) end
  if from == "list" then
    if st.sel ~= i then M.select(i, true) end
    return M.focus_plot()
  end
  M.window()
end

-- forget the plots (and close their real windows)
function M.close_plots()
  i3('[title="^GvPlot"] kill')
  if st.run_dir then vim.fn.delete(st.run_dir, "rf") end
  st.plots = {}
  rebuild_items()
  forget_image()
  M.render()
end

function M.focus_plot()
  if not st.shown then M.show() end
  if not valid_win(st.plot_win) then return notify("No plot or file yet") end
  vim.api.nvim_set_current_win(st.plot_win)
end

-- Space r z / z: go to the viewer and zoom in
function M.zoom()
  M.focus_plot()
  if valid_win(st.plot_win) then M.zoom_in() end
end

-- show / hide the card ---------------------------------------------------------

function M.show(enter)
  hide_pill()
  local back = vim.api.nvim_get_current_win()
  st.shown, st.geo = true, nil
  M.render()
  if enter then vim.api.nvim_set_current_win(st.res_win) elseif valid_win(back) then vim.api.nvim_set_current_win(back) end
end

function M.hide()
  forget_image()
  zoomer_stop()
  if st.zoom.z > 1.001 then st.zoom = { z = 1, cx = 0.5, cy = 0.5, key = st.zoom.key } end
  for _, f in ipairs(vim.fn.glob(VIEW_DIR .. "/zoom-*.png", false, true)) do drop_file(f) end
  for _, w in ipairs({ st.out_win, st.res_win, st.plot_win }) do
    if valid_win(w) then vim.api.nvim_win_close(w, true) end
  end
  st.out_win, st.res_win, st.plot_win, st.shown = nil, nil, nil, false
  show_pill()
  local edit = require("gv.git").edit_window()
  if valid_win(edit) then pcall(vim.api.nvim_set_current_win, edit) end
end

-- close the card completely, pill too (F5 or Space r p brings it back)
function M.close()
  M.hide()
  hide_pill()
end

function M.toggle() if st.shown then M.hide() else M.show() end end

-- the end of the last run's output (for Claude: Space a r, or a in the card)
function M.last_output()
  if not (st.file and valid_buf(st.term_buf)) then return nil end
  local lines = vim.api.nvim_buf_get_lines(st.term_buf, 0, -1, false)
  while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
  return { file = st.file, text = table.concat(vim.list_slice(lines, math.max(1, #lines - 60)), "\n") }
end

-- for troubleshooting: :lua vim.print(require("gv.run").debug())
function M.debug()
  return { shown = st.shown, job = st.job, run_dir = st.run_dir, items = st.items, sel = st.sel, zoom = st.zoom, geo = st.geo,
    drawn = st.drawn, zoomer = { job = zoomer.job, busy = zoomer.busy, want = zoomer.want, err = zoomer.err },
    terminal = Snacks.image.terminal.env(), placement = st.placement and st.placement._state }
end

function M.focus_output()
  if not st.shown then M.show() end
  vim.api.nvim_set_current_win(st.out_win)
  if st.job then vim.cmd.startinsert() end
end

-- running --------------------------------------------------------------------

local function stop_timer()
  if st.timer then st.timer:stop(); st.timer:close(); st.timer = nil end
end

local function finished(code, buf)
  if buf ~= st.term_buf then return end            -- an older, replaced run
  st.job, st.code, st.stopped = nil, code, st.interrupted and code ~= 0
  st.elapsed = (vim.uv.hrtime() - st.start) / 1e9
  -- still typing into the program when it ended: leave typing mode, or the next
  -- key would make Neovim close the finished terminal (and the Output pane)
  if vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_mode().mode == "t" then
    vim.api.nvim_feedkeys(vim.keycode("<C-\\><C-n>"), "n", false)
  end
  stop_timer()
  local lines = unwrap(vim.api.nvim_buf_get_lines(buf, 0, -1, false), st.term_width or 80)
  st.error, st.frames, st.compile = parse(lines, st.cwd)
  if code == 0 then st.error, st.frames = nil, {} end
  st.files = changed_files()
  rebuild_items()
  check_plots()                                    -- figures saved when the program exited
  M.render()
  local name = vim.fn.fnamemodify(st.file, ":t")
  local msg = (st.stopped and "■ " or code == 0 and "✓ " or "✗ ") .. name .. "  ·  " .. fmt_time(st.elapsed)
  if not st.shown then notify(msg, (code == 0 or st.stopped) and vim.log.levels.INFO or vim.log.levels.ERROR) end
  if st.elapsed > 20 and not st.stopped then       -- long runs: a desktop notification too
    vim.system({ "notify-send", "-a", "GaussianVim", code == 0 and "Run finished" or "Run failed", msg })
  end
end

local function start(cmd, file, cwd, console)
  if st.job then pcall(vim.fn.jobstop, st.job) end
  st.interrupted, st.stopped, st.console = false, false, console or false
  i3('[title="^GvPlot"] kill')                     -- real plot windows of the last run
  forget_image()
  zoomer_stop()
  vim.fn.delete(PLOT_DIR, "rf")                    -- last run's plots, zooms and their cached copies
  forget_cached("*-plot-[0-9]*")
  forget_cached("*-zoom-[0-9]*")
  forget_cached("*-file-*")
  st.runs = st.runs + 1
  st.run_dir = ("%s/run-%d-%d-%d"):format(PLOT_DIR, os.time(), vim.fn.getpid(), st.runs)
  vim.fn.mkdir(st.run_dir, "p")
  st.plots, st.files, st.items, st.sel = {}, {}, {}, nil
  st.zoom = { z = 1, cx = 0.5, cy = 0.5 }
  st.file, st.cwd, st.code, st.error, st.frames, st.compile = file, cwd, nil, nil, {}, {}
  st.before = snapshot(cwd)
  M.show()
  local old = st.term_buf
  local buf = vim.api.nvim_create_buf(false, true)
  st.term_buf = buf
  vim.api.nvim_win_set_buf(st.out_win, buf)
  style(st.out_win)
  st.term_width = vim.api.nvim_win_get_width(st.out_win)     -- the width the program sees
  vim.api.nvim_win_call(st.out_win, function()
    st.job = vim.fn.jobstart(cmd, {
      term = true, cwd = cwd,
      env = {
        MPLBACKEND = "module://gvplot", GV_PLOT_DIR = st.run_dir,
        PYTHONPATH = RUNNER .. (vim.env.PYTHONPATH and (":" .. vim.env.PYTHONPATH) or ""),
      },
      on_exit = function(_, code) vim.schedule(function() finished(code, buf) end) end,
    })
  end)
  vim.bo[buf].filetype, vim.bo[buf].bufhidden = "gvrunterm", "hide"
  M.keys(buf)
  -- typing into the program: Ctrl+C / Ctrl+Z stop it too (in the console Ctrl+C
  -- just interrupts the line, as usual)
  vim.keymap.set("t", "<C-c>", function()
    if st.console then pcall(vim.fn.chansend, st.job, "\3") else M.stop() end
  end, { buffer = buf, silent = true })
  vim.keymap.set("t", "<C-z>", M.stop, { buffer = buf, silent = true })
  if valid_buf(old) and old ~= buf then pcall(vim.api.nvim_buf_delete, old, { force = true }) end
  st.start = vim.uv.hrtime()
  M.render()
  stop_timer()
  st.timer = vim.uv.new_timer()
  local ticks = 0
  st.timer:start(300, 300, vim.schedule_wrap(function()
    if not st.job then return end
    check_plots()
    M.render()                                     -- the timer in the status line
    ticks = ticks + 1
    if ticks % 7 == 0 then                        -- every ~2 s: files written so far
      local files = changed_files()
      local function sig(list)
        local s = {}
        for _, f in ipairs(list) do s[#s + 1] = f.path .. ":" .. f.size end
        return table.concat(s, "|")
      end
      if sig(files) ~= sig(st.files) then st.files = files; rebuild_items(); M.render() end
    end
    if valid_win(st.out_win) and vim.api.nvim_get_current_win() ~= st.out_win then   -- newest output in view
      pcall(vim.api.nvim_win_set_cursor, st.out_win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end))
end

-- the file to run: the one you're editing (or the last one, from inside the card)
local CARD_FT = { gvrun = true, gvrunterm = true, gvrunpill = true, gvrunplot = true, gvrunview = true }
local function target()
  local buf = vim.api.nvim_get_current_buf()
  if CARD_FT[vim.bo[buf].filetype] then
    if not st.file then return nil end
    buf = vim.fn.bufnr(st.file)
  end
  return buf
end

function M.run(args)
  local buf = target()
  if not buf or buf < 0 then return notify("Open a file and press F5", vim.log.levels.WARN) end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return notify("Save the file first (Space w)", vim.log.levels.WARN) end
  if vim.bo[buf].modified then vim.api.nvim_buf_call(buf, function() vim.cmd.write() end) end
  local ft = vim.bo[buf].filetype
  local make = RUNNERS[ft]
  local cmd
  if make then
    cmd = make(file)
  elseif vim.fn.executable(file) == 1 then
    cmd = { file }
  elseif ft == "tex" or ft == "plaintex" then
    return require("gv.tex").compile()            -- LaTeX: latexmk, then on every save
  else
    return notify("Don't know how to run a ." .. vim.fn.fnamemodify(file, ":e") .. " file", vim.log.levels.WARN)
  end
  args = args or st.args[file]
  if args and args ~= "" then vim.list_extend(cmd, vim.split(args, "%s+", { trimempty = true })) end
  start(cmd, file, vim.fs.dirname(file))
end

function M.run_with_args()
  local buf = target()
  local file = buf and buf > 0 and vim.api.nvim_buf_get_name(buf) or ""
  vim.ui.input({ prompt = "Arguments", default = st.args[file] or "" }, function(a)
    if a == nil then return end
    st.args[file] = a
    M.run(a)
  end)
end

-- Stop the program. First like Ctrl+C in a terminal (Python then shows the
-- line it was on); if it is still running 2 s later, or you stop it again, it
-- is killed. In the Python console (Space r i) Ctrl+C only interrupts the
-- current command, as in any console; stopping twice ends the console.
function M.stop()
  local job = st.job
  if not job then
    local ft = vim.bo.filetype
    if ft == "tex" or ft == "plaintex" then return require("gv.tex").stop() end   -- LaTeX compiling
    return notify("Nothing is running")
  end
  if st.interrupted then return vim.fn.jobstop(job) end
  st.interrupted = true
  pcall(vim.fn.chansend, job, "\3")
  if st.console then
    vim.defer_fn(function() if st.job == job then st.interrupted = false end end, 1500)
    return
  end
  vim.defer_fn(function()
    if st.job == job then vim.fn.jobstop(job) end
  end, 2000)
end

-- Python console with the file run first: its variables stay to inspect (like Spyder)
function M.console()
  local buf = target()
  if not buf or buf < 0 or vim.bo[buf].filetype ~= "python" then return notify("Open a Python file first", vim.log.levels.WARN) end
  local file = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].modified then vim.api.nvim_buf_call(buf, function() vim.cmd.write() end) end
  start({ python_bin(), "-i", "-u", file }, file, vim.fs.dirname(file), true)
  M.focus_output()
end

-- Enter in Results: a plot / file (see open_item), or the error line
function M.open_here()
  local row = st.rows[vim.api.nvim_win_get_cursor(0)[1]]
  if not row then return end
  if row.item then return M.open_item(row.item, "list") end
  if row.file then open_in_editor(row.file, row.line, row.col) end
end

-- keys inside the card
function M.keys(buf)
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true }) end
  map("q", M.hide)
  map("<Esc>", M.hide)
  map("Q", M.close)
  map("s", M.stop)
  map("<C-c>", M.stop)
  map("<C-z>", M.stop)                            -- never suspend the program (or gv)
  map("r", function() M.run() end)
  map("c", M.close_plots)
  map("f", M.focus_plot)
  map("w", M.window)
  map("o", M.open_app)
  map("a", function() require("gv.claude").run_failed() end)   -- ask Claude why the run failed
  map("]", function() M.next_item(1) end)
  map("[", function() M.next_item(-1) end)
  map("<Tab>", function()                         -- Output → Results → viewer → Output
    local order = vim.tbl_filter(valid_win, { st.out_win, st.res_win, st.plot_win })
    local cur = vim.api.nvim_get_current_win()
    for i, w in ipairs(order) do
      if w == cur then return vim.api.nvim_set_current_win(order[i % #order + 1]) end
    end
    if order[1] then vim.api.nvim_set_current_win(order[1]) end
  end)
  if buf == st.res_buf then
    map("<CR>", M.open_here)
    map("<2-LeftMouse>", M.open_here)
    map("z", M.zoom)
    map("+", M.zoom)
  elseif buf == st.plot_buf then
    map("<CR>", function() M.open_item(st.sel, "view") end)
    for _, k in ipairs({ "z", "+", "=" }) do map(k, function() M.zoom_in() end) end
    for _, k in ipairs({ "Z", "-" }) do map(k, function() M.zoom_out() end) end
    map("0", M.zoom_fit)
    -- mouse: double-click zooms in there, drag moves a zoomed picture; clicks
    -- anywhere else still do what they always do
    local function mouse(lhs, fn)
      vim.keymap.set("n", lhs, function()
        local m = vim.fn.getmousepos()
        local here = m.winid == st.plot_win and zoomable(st.items[st.sel or 0])
        if here or lhs == "<LeftRelease>" then vim.schedule(function() fn(m) end) end
        if here and (lhs == "<2-LeftMouse>" or (lhs == "<LeftDrag>" and st.zoom.z > 1.001)) then return "" end
        return lhs
      end, { buffer = buf, expr = true, nowait = true, silent = true })
    end
    mouse("<2-LeftMouse>", function(m) M.zoom_to(st.zoom.z * 2, m) end)
    mouse("<LeftMouse>", function(m) M.drag("press", m) end)
    mouse("<LeftDrag>", function(m) M.drag("move", m) end)
    mouse("<LeftRelease>", function(m) M.drag("release", m) end)
    -- move around when zoomed; otherwise step through the plots / files
    local function nav(dx, dy, step)
      return function()
        if st.zoom.z > 1.001 then M.pan(dx * 0.25, dy * 0.25) elseif step then M.next_item(step) end
      end
    end
    for _, k in ipairs({ "h", "<Left>" }) do map(k, nav(-1, 0, -1)) end
    for _, k in ipairs({ "l", "<Right>" }) do map(k, nav(1, 0, 1)) end
    for _, k in ipairs({ "k", "<Up>" }) do map(k, nav(0, -1, -1)) end
    for _, k in ipairs({ "j", "<Down>" }) do map(k, nav(0, 1, 1)) end
  elseif buf == st.view_buf then
    map("<CR>", function() M.open_item(st.sel, "view") end)
    map("<2-LeftMouse>", function() M.open_item(st.sel, "view") end)
  end
end

-- the mouse wheel over a picture in the viewer zooms it (at the mouse), even
-- when the cursor is in the editor; everywhere else it scrolls as usual
for _, dir in ipairs({ "Up", "Down" }) do
  local lhs = "<ScrollWheel" .. dir .. ">"
  vim.keymap.set("n", lhs, function()
    local m = vim.fn.getmousepos()
    if valid_win(st.plot_win) and m.winid == st.plot_win and zoomable(st.items[st.sel or 0]) then
      vim.schedule(function()
        if dir == "Up" then M.zoom_in(m) else M.zoom_out(m) end
      end)
      return ""
    end
    return lhs
  end, { expr = true, desc = "Scroll (zooms a picture in the run card)" })
end

-- Ctrl+C / Ctrl+Z in the editor (normal mode) stop the run while one is
-- running; otherwise they do what they always do
for _, lhs in ipairs({ "<C-c>", "<C-z>" }) do
  vim.keymap.set("n", lhs, function()
    if st.job then vim.schedule(M.stop); return "" end
    return lhs
  end, { expr = true, desc = "Stop the run (while one is running)" })
end

-- clicking the pill opens the card; resizing re-lays the card out
vim.api.nvim_create_autocmd("WinEnter", {
  callback = function()
    if valid_win(st.pill) and vim.api.nvim_get_current_win() == st.pill then
      vim.schedule(function() vim.cmd.wincmd("p"); M.show() end)
    end
  end,
})
vim.api.nvim_create_autocmd("VimResized", {
  callback = function()
    if st.shown then M.show() elseif valid_win(st.pill) then update_titles() end
  end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if st.job then pcall(vim.fn.jobstop, st.job) end
    zoomer_stop()
  end,
})

return M
