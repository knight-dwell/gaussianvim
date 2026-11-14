-- Floating panels you can move, resize, hide and copy from: Claude, Stack
-- Exchange answers, docs, wiki, floating terminals, hover help, ...
--
--   mouse   drag the top or left edge (the title bar) to move a panel,
--           the bottom or right edge (the corner: both) to resize it;
--           select text with the mouse and it is copied when you let go
--   keys    Alt + arrows          move
--           Alt + Shift + arrows  narrower / wider / shorter / taller
--           Alt + =  /  Alt + -   bigger / smaller
--           Alt + m               fill the screen / back
--           Ctrl + q              hide it to the dock (status line, bottom right)
--   copy    y in a selection copies to the system clipboard (as everywhere);
--           in a panel, a mouse selection is copied by itself
-- A panel remembers where you put it and how big it was, also after hiding.
local M = {}
local api = vim.api

-- panels with their own layout or that come and go by themselves
local SKIP = {
  snacks_layout_box = true, snacks_notif = true, snacks_notif_history = true, snacks_input = true,
  snacks_dashboard = true, noice = true, notify = true, ["which_key"] = true, wk = true,
  TelescopePrompt = true, TelescopeResults = true, gvscm = true, gvmenu = true, gitcommit = false,
}
local SKIP_PREFIX = { "gvrun", "blink", "cmp_", "snacks_picker", "snacks_notif", "dapui" }

function M.managed(win)
  win = win or api.nvim_get_current_win()
  if not (win and api.nvim_win_is_valid(win)) then return false end
  local c = api.nvim_win_get_config(win)
  if c.relative == "" or c.focusable == false or c.hide or c.external then return false end
  if vim.w[win].gv_float == false then return false end
  local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
  if SKIP[ft] then return false end
  for _, p in ipairs(SKIP_PREFIX) do if ft:sub(1, #p) == p then return false end end
  return true
end

local function has_border(c)
  local b = c.border
  if not b or b == "none" or b == "" then return false end
  if type(b) == "table" then
    for _, ch in ipairs(b) do
      local s = type(ch) == "table" and ch[1] or ch
      if s and s ~= "" then return true end
    end
    return false
  end
  return true
end

-- where a panel is, in editor cells (outer top-left, inner size)
local function geom(win)
  local c = api.nvim_win_get_config(win)
  local pos = api.nvim_win_get_position(win)
  return { row = pos[1], col = pos[2], width = c.width, height = c.height, b = has_border(c) and 2 or 0 }
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function apply(win, g, save)
  local maxw, maxh = vim.o.columns - g.b, vim.o.lines - vim.o.cmdheight - 1 - g.b
  g.width, g.height = clamp(math.floor(g.width), 8, math.max(8, maxw)), clamp(math.floor(g.height), 2, math.max(2, maxh))
  -- stays on screen: pushed back in (whole) when the screen got smaller, e.g. the PDF pane opened
  g.row = clamp(math.floor(g.row), 0, math.max(0, vim.o.lines - vim.o.cmdheight - 1 - g.b - g.height))
  g.col = clamp(math.floor(g.col), 0, math.max(0, vim.o.columns - g.b - g.width))
  pcall(api.nvim_win_set_config, win, { relative = "editor", row = g.row, col = g.col, width = g.width, height = g.height })
  if save ~= false then
    local buf = api.nvim_win_get_buf(win)
    vim.b[buf].gv_geom = { row = g.row, col = g.col, width = g.width, height = g.height }
  end
end

function M.move(win, dr, dc)
  local g = geom(win); g.row, g.col = g.row + dr, g.col + dc; apply(win, g)
end

function M.resize(win, dw, dh)
  local g = geom(win); g.width, g.height = g.width + dw, g.height + dh; apply(win, g)
end

function M.scale(win, f)
  local g = geom(win)
  local nw, nh = math.floor(g.width * f + 0.5), math.floor(g.height * f + 0.5)
  if nw == g.width then nw = nw + (f > 1 and 2 or -2) end
  if nh == g.height then nh = nh + (f > 1 and 1 or -1) end
  g.row, g.col = g.row - math.floor((nh - g.height) / 2), g.col - math.floor((nw - g.width) / 2)
  g.width, g.height = nw, nh
  apply(win, g)
end

function M.maximize(win)
  local buf = api.nvim_win_get_buf(win)
  local g = geom(win)
  if vim.b[buf].gv_unmax then
    local o = vim.b[buf].gv_unmax
    vim.b[buf].gv_unmax = nil
    return apply(win, { row = o.row, col = o.col, width = o.width, height = o.height, b = g.b })
  end
  vim.b[buf].gv_unmax = { row = g.row, col = g.col, width = g.width, height = g.height }
  apply(win, { row = 0, col = 0, width = vim.o.columns - g.b, height = vim.o.lines - vim.o.cmdheight - 2 - g.b, b = g.b })
end

-- a panel shown again (Claude after Space a a, ...) goes back where you put it
local function reapply(win)
  if not M.managed(win) then return end
  local saved = vim.b[api.nvim_win_get_buf(win)].gv_geom
  if not saved then return end
  local g = vim.deepcopy(saved); g.b = geom(win).b
  apply(win, g, false)
end

local function title_of(win, buf)
  local c = api.nvim_win_get_config(win)
  local t = c.title
  if type(t) == "table" then
    local s = {}
    for _, chunk in ipairs(t) do s[#s + 1] = type(chunk) == "table" and chunk[1] or chunk end
    t = table.concat(s)
  end
  t = vim.trim(t or "")
  if t == "" then
    local name = api.nvim_buf_get_name(buf)
    t = name ~= "" and vim.fn.fnamemodify(name, ":t") or (vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "panel")
  end
  return t
end

-- Ctrl+q in a panel: hide it to the dock
function M.minimize(win)
  win = win or api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  local cfg = api.nvim_win_get_config(win)
  local g = geom(win)
  vim.b[buf].gv_geom = { row = g.row, col = g.col, width = g.width, height = g.height }
  cfg.relative, cfg.row, cfg.col, cfg.win, cfg.bufpos = "editor", g.row, g.col, nil, nil
  local wo = { wrap = vim.wo[win].wrap, linebreak = vim.wo[win].linebreak, conceallevel = vim.wo[win].conceallevel,
    winhighlight = vim.wo[win].winhighlight, number = vim.wo[win].number, cursorline = vim.wo[win].cursorline }
  local cursor = api.nvim_win_get_cursor(win)
  local was_term = vim.bo[buf].buftype == "terminal" and vim.fn.mode() == "t"
  if vim.bo[buf].bufhidden ~= "" and vim.bo[buf].bufhidden ~= "hide" then vim.bo[buf].bufhidden = "hide" end
  local title = title_of(win, buf)
  require("gv.dock").add({
    key = "buf" .. buf, name = title, icon = vim.bo[buf].buftype == "terminal" and "\u{f018d}" or "\u{f05b7}",
    valid = function() return api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) == -1 end,
    restore = function()
      local w = api.nvim_open_win(buf, true, cfg)
      for k, v in pairs(wo) do pcall(function() vim.wo[w][k] = v end) end
      pcall(api.nvim_win_set_cursor, w, cursor)
      if was_term then vim.cmd.startinsert() end
    end,
  })
  if vim.fn.mode() ~= "n" then vim.cmd("stopinsert") end
  api.nvim_win_hide(win)
  vim.notify(("%s hidden: click it in the bar at the bottom right (or Ctrl+q) to bring it back"):format(title),
    vim.log.levels.INFO, { title = "Dock" })
end

-- keys ---------------------------------------------------------------------------
local function feed(key) api.nvim_feedkeys(vim.keycode(key), "ni", false) end

-- key: what it does in a panel; elsewhere the key does what it did before
local function panel_key(lhs, fn, desc, fallback)
  vim.keymap.set({ "n", "i", "t", "x" }, lhs, function()
    local win = api.nvim_get_current_win()
    if M.managed(win) then return fn(win) end
    if fallback then return fallback() end
    feed(lhs)
  end, { desc = desc })
end

panel_key("<A-Left>", function(w) M.move(w, 0, -4) end, "Panel: move left")
panel_key("<A-Right>", function(w) M.move(w, 0, 4) end, "Panel: move right")
panel_key("<A-Up>", function(w) M.move(w, -2, 0) end, "Panel: move up")
panel_key("<A-Down>", function(w) M.move(w, 2, 0) end, "Panel: move down")
panel_key("<A-S-Left>", function(w) M.resize(w, -4, 0) end, "Panel: narrower")
panel_key("<A-S-Right>", function(w) M.resize(w, 4, 0) end, "Panel: wider")
panel_key("<A-S-Up>", function(w) M.resize(w, 0, -2) end, "Panel: shorter")
panel_key("<A-S-Down>", function(w) M.resize(w, 0, 2) end, "Panel: taller")
panel_key("<A-=>", function(w) M.scale(w, 1.15) end, "Panel: bigger")
panel_key("<A-->", function(w) M.scale(w, 1 / 1.15) end, "Panel: smaller")
panel_key("<A-m>", function(w) M.maximize(w) end, "Panel: fill the screen / back")
panel_key("<C-q>", function(w) M.minimize(w) end, "Hide the panel to the dock / bring the last one back", function()
  if vim.fn.mode() ~= "n" then return feed("<C-q>") end
  if require("gv.dock").restore_last() then return end
  local open = vim.iter(vim.fn.getwininfo()):any(function(w) return w.quickfix == 1 end)
  vim.cmd(open and "cclose" or "copen")
end)

-- mouse: drag edges to move / resize, a selection is copied when you let go -------
local drag            -- { win, mode = "move" | "resize", r0, c0, g, right, bottom }
local selecting       -- a mouse selection in a panel is going on

vim.keymap.set({ "n", "i", "t", "x" }, "<LeftMouse>", function()
  selecting = nil
  local m = vim.fn.getmousepos()
  local win = m.winid
  if win ~= 0 and M.managed(win) then
    local c = api.nvim_win_get_config(win)
    if has_border(c) and m.line == 0 then
      local top, bottom = m.winrow == 1, m.winrow == c.height + 2
      local left, right = m.wincol == 1, m.wincol == c.width + 2
      if top or bottom or left or right then
        drag = { win = win, mode = (bottom or right) and not top and not left and "resize" or "move",
          r0 = m.screenrow, c0 = m.screencol, g = geom(win), right = right, bottom = bottom }
        if api.nvim_get_current_win() ~= win then
          if vim.fn.mode() ~= "n" then vim.cmd("stopinsert") end
          pcall(api.nvim_set_current_win, win)
        end
        return
      end
    end
  end
  drag = nil
  feed("<LeftMouse>")
end, { desc = "Click (drag a panel's edge: move / resize)" })

vim.keymap.set({ "n", "i", "t", "x" }, "<LeftDrag>", function()
  if drag then
    if not api.nvim_win_is_valid(drag.win) then drag = nil; return end
    local m = vim.fn.getmousepos()
    local dr, dc = m.screenrow - drag.r0, m.screencol - drag.c0
    local g = vim.deepcopy(drag.g)
    if drag.mode == "move" then g.row, g.col = g.row + dr, g.col + dc
    else
      if drag.right then g.width = g.width + dc end
      if drag.bottom then g.height = g.height + dr end
    end
    apply(drag.win, g)
    return
  end
  if M.managed() then selecting = api.nvim_get_current_win() end
  feed("<LeftDrag>")
end, { desc = "Drag" })

vim.keymap.set({ "n", "i", "t", "x" }, "<LeftRelease>", function()
  if drag then drag = nil; return end
  local win = selecting
  selecting = nil
  if not win then return feed("<LeftRelease>") end
  -- copy once the release (and the drags before it) have made the selection
  M._sel_win = win
  api.nvim_feedkeys(vim.keycode("<LeftRelease><Cmd>lua require('gv.floatwin')._copy_selection()<CR>"), "ni", false)
end, { desc = "Release (a mouse selection in a panel is copied)" })

function M._copy_selection()
  local win = M._sel_win
  M._sel_win = nil
  if not win or api.nvim_get_current_win() ~= win or not vim.fn.mode():match("^[vV\22]") then return end
  local buf = api.nvim_win_get_buf(win)
  vim.cmd('normal! "+y')
  local text = vim.fn.getreg("+")
  local n = select(2, text:gsub("\n", "")) + 1
  vim.notify(("Copied %d line%s"):format(n, n == 1 and "" or "s"), vim.log.levels.INFO, { title = "Clipboard" })
  if vim.bo[buf].buftype == "terminal" then vim.cmd.startinsert() end    -- Claude: keep typing
end

-- keep panels where you put them ---------------------------------------------------
local grp = api.nvim_create_augroup("gv_floatwin", { clear = true })
api.nvim_create_autocmd("BufWinEnter", {
  group = grp,
  callback = function(ev)
    vim.schedule(function()
      local win = vim.fn.bufwinid(ev.buf)
      if win ~= -1 then reapply(win) end
    end)
  end,
})
api.nvim_create_autocmd("VimResized", {
  group = grp,
  callback = function()
    vim.defer_fn(function()            -- after the panels' own resize handlers
      for _, w in ipairs(api.nvim_list_wins()) do reapply(w) end
    end, 30)
  end,
})

return M
