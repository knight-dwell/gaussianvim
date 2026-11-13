-- Typeset LaTeX maths in a reading window (Stack Exchange answers, docs): every
-- $...$ / $$...$$ in the buffer is compiled once with pdflatex, turned into a
-- transparent PNG by ImageMagick (cached in ~/.cache/gaussianvim/math) and drawn
-- over its source by kitty (Snacks.image). Inline maths stays on its line;
-- $$...$$ is drawn on its own line(s). Without kitty graphics the LaTeX shows as text.
--
--   require("gv.mathrender").render(buf)
local M = {}
local CACHE = vim.fn.stdpath("cache") .. "/math"
local MAX_JOBS = 4

local function fg_hex()
  local hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  return hl.fg and ("%06x"):format(hl.fg) or "e2e2e9"
end

-- what LaTeX can compile in a standalone page
local function tex_source(formula, display, color)
  formula = formula:gsub("\\begin{align%*?}", "\\begin{aligned}"):gsub("\\end{align%*?}", "\\end{aligned}")
    :gsub("\\begin{equation%*?}", ""):gsub("\\end{equation%*?}", ""):gsub("\\label{[^}]*}", ""):gsub("\\tag{[^}]*}", "")
  return table.concat({
    "\\documentclass[border=1pt]{standalone}",
    "\\usepackage{amsmath,amssymb,amsfonts,mathtools,bm,xcolor}",
    "\\providecommand{\\ket}[1]{\\left|#1\\right\\rangle}\\providecommand{\\bra}[1]{\\left\\langle#1\\right|}",
    "\\providecommand{\\braket}[2]{\\left\\langle#1\\middle|#2\\right\\rangle}",
    "\\begin{document}\\color[HTML]{" .. color .. "}",
    display and ("$\\displaystyle " .. formula .. "$") or ("$" .. formula .. "$"),
    "\\end{document}",
  }, "\n")
end

-- compile one formula (async, cached by content); cb(png or nil)
local queue, running = {}, 0
local function pump()
  while running < MAX_JOBS and #queue > 0 do
    local job = table.remove(queue, 1)
    running = running + 1
    local base = CACHE .. "/" .. job.hash
    local f = io.open(base .. ".tex", "w")
    f:write(job.src)
    f:close()
    vim.system({ "sh", "-c", ('pdflatex -interaction=nonstopmode -halt-on-error -output-directory "%s" "%s.tex" >/dev/null 2>&1 && magick -density 220 -background none "%s.pdf" -trim +repage "%s.png" >/dev/null 2>&1; rm -f "%s.aux" "%s.log"')
      :format(CACHE, base, base, base, base, base) }, {}, function()
      vim.schedule(function()
        running = running - 1
        job.cb(vim.uv.fs_stat(base .. ".png") and (base .. ".png") or nil)
        pump()
      end)
    end)
  end
end

local function png_for(formula, display, color, cb)
  vim.fn.mkdir(CACHE, "p")
  local src = tex_source(formula, display, color)
  local hash = vim.fn.sha256(src):sub(1, 16)
  local png = CACHE .. "/" .. hash .. ".png"
  if vim.uv.fs_stat(png) then return cb(png) end
  if vim.uv.fs_stat(CACHE .. "/" .. hash .. ".pdf") then return cb(nil) end   -- failed before: leave as text
  queue[#queue + 1] = { hash = hash, src = src, cb = cb }
  pump()
end

-- the $...$ / $$...$$ spans of each line (rows 1-based, cols 0-based, end exclusive)
local function spans(lines)
  local out = {}
  for row, l in ipairs(lines) do
    local i = 1
    while i <= #l do
      local s = l:find("%$", i)
      if not s then break end
      if s > 1 and l:sub(s - 1, s - 1) == "\\" then
        i = s + 1
      else
        local display = l:sub(s, s + 1) == "$$"
        local open = display and 2 or 1
        local e = l:find(display and "%$%$" or "%$", s + open)
        while e and l:sub(e - 1, e - 1) == "\\" do e = l:find(display and "%$%$" or "%$", e + 1) end
        if not e then break end
        local formula = l:sub(s + open, e - 1)
        if vim.trim(formula) ~= "" then
          out[#out + 1] = { row = row, s = s - 1, e = e - 1 + open, formula = formula, display = display }
        end
        i = e + open
      end
    end
  end
  return out
end

function M.render(buf)
  if not (Snacks and Snacks.image and Snacks.image.supports_terminal()) then return end
  -- Markdown with the latex parser installed: Snacks typesets the maths itself
  if vim.bo[buf].filetype == "markdown" and pcall(vim.treesitter.language.add, "latex")
    and vim.treesitter.language.add("latex") then return end
  if vim.fn.executable("pdflatex") == 0 or vim.fn.executable("magick") == 0 then return end
  local color = fg_hex()
  local width = 100
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do width = vim.api.nvim_win_get_width(w) end
  for _, sp in ipairs(spans(vim.api.nvim_buf_get_lines(buf, 0, -1, false))) do
    png_for(sp.formula, sp.display, color, function(png)
      if not png or not vim.api.nvim_buf_is_valid(buf) then return end
      pcall(Snacks.image.placement.new, buf, png, {
        pos = { sp.row, sp.s }, range = { sp.row, sp.s, sp.row, sp.e }, inline = true, conceal = true,
        max_width = math.max(10, width - 4), max_height = sp.display and 8 or 1,
      })
    end)
  end
end

return M
