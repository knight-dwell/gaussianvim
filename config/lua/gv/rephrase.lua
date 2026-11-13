-- Rephrase with your local Qwen (~/local-llm, `qwen-server`), for LaTeX:
--
--   Space l p        the paragraph under the cursor (visual mode: the selection)
--
-- A card opens below the text and Qwen's version appears in it as it is
-- written; the words it changed are highlighted. In the card:
--
--   Enter   put it in your text (u undoes)     r   try again
--   s       shorter     g   fix only grammar   f   more formal   i   improve
--   q / Esc leave your text as it was
--
-- \commands, maths, \cite, \ref and \label are kept as written. The server
-- starts on first use (~15 s); if gv started it, it stops after 10 idle minutes.
local M = {}
local URL = "http://127.0.0.1:8085"
local IDLE_STOP_MS = 10 * 60 * 1000
local ns = vim.api.nvim_create_namespace("gv_rephrase")

local STYLES = {
  improve = { name = "Improve", ask = "Rewrite the text so it reads clearly and flows well, with correct grammar, in formal academic English." },
  shorter = { name = "Shorter", ask = "Rewrite the text so it is noticeably shorter and more direct, with correct grammar, in formal academic English." },
  grammar = { name = "Grammar only", ask = "Correct only the grammar, spelling and punctuation of the text. Change as few words as possible." },
  formal = { name = "More formal", ask = "Rewrite the text in a more formal and precise scientific style suitable for a thesis, with correct grammar." },
}
local SYSTEM = "You edit physics theses written in LaTeX. %s Keep the meaning and do not add facts. "
  .. "Keep every LaTeX command, math ($...$, environments), \\cite{...}, \\ref{...} and \\label{...} exactly as written. "
  .. "Reply with the rewritten text only: no introduction, no explanation, no quotes, no markdown."

local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Rephrase" }) end
local function server_cmd() local p = vim.fn.expand("~/.local/bin/qwen-server"); return vim.fn.executable(p) == 1 and p or "qwen-server" end

-- the server: started when needed, stopped 10 idle minutes later if gv started it
local srv = { ours = false }
local function healthy(cb)
  vim.system({ "curl", "-fs", "--max-time", "2", URL .. "/health" }, {}, function(r)
    vim.schedule(function() cb(r.code == 0) end)
  end)
end

local function touch()
  if not srv.ours then return end
  if srv.timer then srv.timer:stop(); srv.timer:close() end
  srv.timer = vim.uv.new_timer()
  srv.timer:start(IDLE_STOP_MS, 0, vim.schedule_wrap(function()
    if M.card and M.card.job then return touch() end
    vim.system({ server_cmd(), "stop" })
    srv.ours, srv.timer = false, nil
  end))
end

local function ensure_server(cb)
  healthy(function(ok)
    if ok then return cb(true) end
    if vim.fn.executable(server_cmd()) == 0 then
      notify("The local Qwen isn't set up (qwen-server not found)", vim.log.levels.ERROR)
      return cb(false)
    end
    vim.system({ server_cmd(), "start", "-q" }, {}, function(r)
      vim.schedule(function()
        if r.code ~= 0 then
          notify("The local Qwen didn't start. See: qwen-server logs", vim.log.levels.ERROR)
          return cb(false)
        end
        srv.ours = true
        cb(true)
      end)
    end)
  end)
end

-- the text to rephrase -----------------------------------------------------------

-- lines that end a paragraph: blank, comments, \begin / \end, headings, \item, \label
local function boundary(l)
  if l:match("^%s*$") or l:match("^%s*%%") then return true end
  for _, w in ipairs({ "begin", "end", "chapter", "section", "subsection", "subsubsection", "paragraph", "item", "label", "caption" }) do
    if l:match("^%s*\\" .. w .. "%f[%A]") then return true end
  end
  return false
end

local function paragraph()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if boundary(lines[row] or "") then return nil end
  local s, e = row, row
  while s > 1 and not boundary(lines[s - 1]) do s = s - 1 end
  while e < #lines and not boundary(lines[e + 1]) do e = e + 1 end
  return { srow = s - 1, scol = 0, erow = e - 1, ecol = #lines[e], linewise = true }
end

local function selection()
  local mode = vim.fn.visualmode()
  local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  local srow, erow = s[2] - 1, e[2] - 1
  local last = vim.api.nvim_buf_get_lines(0, erow, erow + 1, false)[1] or ""
  if mode == "V" then return { srow = srow, scol = 0, erow = erow, ecol = #last, linewise = true } end
  local ecol = math.min(e[3], #last)                -- e[3] can be huge ($ selections)
  return { srow = srow, scol = s[3] - 1, erow = erow, ecol = ecol, linewise = false }
end

-- words into lines no wider than width (the width your paragraph already had)
local function rewrap(text, width, indent)
  local out = {}
  for _, para in ipairs(vim.split(text, "\n", { plain = true })) do
    local line = ""
    for word in para:gmatch("%S+") do
      if line ~= "" and #indent + #line + 1 + #word > width then
        out[#out + 1] = indent .. line
        line = word
      else
        line = line == "" and word or (line .. " " .. word)
      end
    end
    out[#out + 1] = indent .. line
  end
  return out
end

-- what Qwen sent, without chatter around it
local function clean(text)
  text = text:gsub("<think>.-</think>", "")
  text = vim.trim(text)
  text = text:gsub("^```%w*\n", ""):gsub("\n```$", "")
  local first, rest = text:match("^([^\n]*)\n(.*)$")
  if first and first:match(":%s*$") and first:lower():match("^here") then text = vim.trim(rest) end
  if text:match('^".*"$') then text = text:sub(2, -2) end
  return text
end

-- the card -----------------------------------------------------------------------

local function close_card(accepted)
  local c = M.card
  if not c then return end
  M.card = nil
  if c.job then pcall(function() c.job:kill("sigterm") end) end
  if vim.api.nvim_win_is_valid(c.win) then vim.api.nvim_win_close(c.win, true) end
  if vim.api.nvim_win_is_valid(c.src_win) then
    vim.api.nvim_set_current_win(c.src_win)
    if accepted then pcall(vim.api.nvim_win_set_cursor, c.src_win, { c.range.srow + 1, c.range.scol }) end
  end
  touch()
end

local function set_card_text(c, text, done)
  if not vim.api.nvim_buf_is_valid(c.buf) then return end
  local lines = vim.split(text, "\n", { plain = true })
  vim.bo[c.buf].modifiable = true
  vim.api.nvim_buf_set_lines(c.buf, 0, -1, false, lines)
  vim.bo[c.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(c.buf, ns, 0, -1)
  if not done then return end
  -- highlight the words Qwen changed (a word-by-word diff against your text)
  local old_words = table.concat(vim.split(vim.trim(c.original), "%s+"), "\n") .. "\n"
  local tokens = {}
  for i, l in ipairs(lines) do
    local pos = 1
    while true do
      local s, e = l:find("%S+", pos)
      if not s then break end
      tokens[#tokens + 1] = { row = i - 1, s = s - 1, e = e, w = l:sub(s, e) }
      pos = e + 1
    end
  end
  local new_words = {}
  for i, t in ipairs(tokens) do new_words[i] = t.w end
  local hunks = vim.diff(old_words, table.concat(new_words, "\n") .. "\n", { result_type = "indices" }) or {}
  for _, h in ipairs(hunks) do
    for k = h[3], h[3] + h[4] - 1 do
      local t = tokens[k]
      if t then vim.api.nvim_buf_set_extmark(c.buf, ns, t.row, t.s, { end_col = t.e, hl_group = "GvRephraseNew" }) end
    end
  end
end

local function card_config(c, height)
  local footer = c.job and " q cancel " or " Enter replace · r again · s shorter · g grammar · f formal · q cancel "
  return {
    title = { { (" \u{f0b79} Rephrase · %s%s "):format(STYLES[c.style].name, c.job and "  · Qwen is writing…" or ""), "FloatTitle" } },
    title_pos = "left", footer = { { footer, "FloatFooter" } }, footer_pos = "right", height = height,
  }
end

local function resize(c)
  if not vim.api.nvim_win_is_valid(c.win) then return end
  local h = 0
  local w = vim.api.nvim_win_get_width(c.win)
  for _, l in ipairs(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false)) do
    h = h + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / math.max(1, w - 2)))
  end
  vim.api.nvim_win_set_config(c.win, card_config(c, math.max(2, math.min(h, 16))))
end

local function run(c)
  c.text, c.done = "", false
  set_card_text(c, c.ready and "  Qwen is reading your text…" or "  Starting the local Qwen (about 15 s the first time)…")
  resize(c)
  ensure_server(function(ok)
    if M.card ~= c then return end
    if not ok then return close_card(false) end
    c.ready = true
    set_card_text(c, "  Qwen is reading your text…")
    local body = vim.json.encode({
      model = "qwen-local", stream = true, temperature = c.style == "grammar" and 0.2 or 0.5,
      max_tokens = math.floor(#c.original / 2) + 128,
      chat_template_kwargs = { enable_thinking = false },
      messages = {
        { role = "system", content = SYSTEM:format(STYLES[c.style].ask) },
        { role = "user", content = c.original },
      },
    })
    local partial = ""
    c.job = vim.system({ "curl", "-sN", "--max-time", "300", URL .. "/v1/chat/completions",
      "-H", "Content-Type: application/json", "-d", "@-" }, {
      stdin = body,
      stdout = function(_, data)
        if not data then return end
        partial = partial .. data
        while true do
          local nl = partial:find("\n", 1, true)
          if not nl then break end
          local line = partial:sub(1, nl - 1)
          partial = partial:sub(nl + 1)
          local payload = line:match("^data: (.*)")
          if payload and payload ~= "[DONE]" then
            local ok2, obj = pcall(vim.json.decode, payload)
            local delta = ok2 and type(obj) == "table" and obj.choices and obj.choices[1] and obj.choices[1].delta
            local piece = delta and delta.content
            if type(piece) == "string" and piece ~= "" then
              vim.schedule(function()
                if M.card ~= c then return end
                c.text = c.text .. piece
                set_card_text(c, c.text)
                resize(c)
              end)
            end
          end
        end
      end,
    }, function(r)
      vim.schedule(function()
        if M.card ~= c then return end
        c.job = nil
        c.text = clean(c.text)
        if r.code ~= 0 or c.text == "" then
          set_card_text(c, "  No answer from Qwen. r tries again.")
        else
          c.done = true
          set_card_text(c, c.text, true)
        end
        resize(c)
      end)
    end)
    resize(c)
  end)
end

local function accept()
  local c = M.card
  if not c then return end
  if c.job or not c.done then return notify("Qwen is still writing") end
  local r = c.range
  local now = vim.api.nvim_buf_get_text(c.src_buf, r.srow, r.scol, r.erow, r.ecol, {})
  if table.concat(now, "\n") ~= c.original then
    close_card(false)
    return notify("Your text changed meanwhile; nothing was replaced", vim.log.levels.WARN)
  end
  local new
  if r.linewise and r.erow > r.srow then
    local first = vim.api.nvim_buf_get_lines(c.src_buf, r.srow, r.srow + 1, false)[1] or ""
    local indent = first:match("^%s*")
    local width = 0
    for _, l in ipairs(now) do width = math.max(width, #l) end
    new = rewrap(c.text, math.max(50, math.min(width, 120)), indent)
  else
    new = vim.split(c.text, "\n", { plain = true })
  end
  vim.api.nvim_buf_set_text(c.src_buf, r.srow, r.scol, r.erow, r.ecol, new)
  close_card(true)
  notify("Replaced. u undoes it")
end

-- Space l p: from normal mode the paragraph, from visual mode the selection
function M.start(from_visual)
  if M.card then close_card(false) end
  local range = from_visual and selection() or paragraph()
  if not range then return notify("Put the cursor inside a paragraph of text") end
  local src_buf, src_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local original = table.concat(vim.api.nvim_buf_get_text(src_buf, range.srow, range.scol, range.erow, range.ecol, {}), "\n")
  if vim.trim(original) == "" then return notify("Nothing to rephrase here") end
  -- the card goes right below the text (above it when there is no room)
  local width = math.min(vim.api.nvim_win_get_width(src_win) - 4, 100)
  local below = vim.fn.screenpos(src_win, range.erow + 1, 1).row
  local above = vim.fn.screenpos(src_win, range.srow + 1, 1).row
  local row = below > 0 and (below + 1) or 2
  if row + 8 > vim.o.lines - 2 and above > 10 then row = math.max(1, above - 10) end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local c = { buf = buf, src_buf = src_buf, src_win = src_win, range = range, original = original, style = "improve" }
  c.win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("force", {
    relative = "editor", row = row - 1, col = vim.fn.win_screenpos(src_win)[2] + 1, width = width,
    style = "minimal", border = "rounded", zindex = 60,
  }, card_config(c, 3)))
  vim.wo[c.win].wrap, vim.wo[c.win].linebreak = true, true
  vim.wo[c.win].winhighlight = "Normal:GvMenu,NormalNC:GvMenu,FloatBorder:GvMenuBorder"
  M.card = c
  local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true }) end
  map("<CR>", accept)
  map("a", accept)
  map("q", function() close_card(false) end)
  map("<Esc>", function() close_card(false) end)
  for key, style in pairs({ r = false, i = "improve", s = "shorter", g = "grammar", f = "formal" }) do
    map(key, function()
      if c.job then return notify("Qwen is still writing (q cancels)") end
      if style then c.style = style end
      run(c)
    end)
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf, once = true,
    callback = function() vim.schedule(function() if M.card == c then close_card(false) end end) end,
  })
  run(c)
end

vim.api.nvim_set_hl(0, "GvRephraseNew", { default = true, link = "DiagnosticOk" })
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function() if srv.ours then vim.system({ server_cmd(), "stop" }):wait(3000) end end,
})

return M
