-- GaussianVim's Material You look: the rice palette applied to every part of
-- the editor (cards, menus, status line, tabs, completion, pickers, errors).
--
-- Colors come from ~/.config/theme/generated/gaussianvim-colors.lua (rendered by
-- the rice's apply-theme.sh, so the editor follows the wallpaper/theme); the
-- table below is the same palette, used when that file doesn't exist.
local M = {}

local DEFAULT = {
  bg = "#111318", bg_dim = "#111318", bg_low = "#1a1b20", bg_float = "#1e1f25",
  bg_high = "#282a2f", bg_highest = "#33353a",
  fg = "#e2e2e9", fg_dim = "#c4c6d0", outline = "#8e9099", outline_variant = "#44474f",
  primary = "#adc6ff", on_primary = "#102f60", primary_container = "#2b4678", on_primary_container = "#d8e2ff",
  secondary = "#bfc6dc", on_secondary = "#293041", secondary_container = "#3f4759", on_secondary_container = "#dbe2f9",
  tertiary = "#debcdf", on_tertiary = "#402843", tertiary_container = "#583e5b", on_tertiary_container = "#fbd7fc",
  error = "#ffb4ab", on_error = "#690005", error_container = "#93000a", on_error_container = "#ffdad6",
  red = "#ef6f6c", red_b = "#ff8a87", green = "#7fc98f", green_b = "#9ee2ab",
  yellow = "#e6c07b", yellow_b = "#f2d49b", blue = "#6fa8f5", blue_b = "#92bdf8",
  magenta = "#c58af9", magenta_b = "#d6a8fb", cyan = "#5cc8c8", cyan_b = "#82dada", grey = "#5c5f69",
}

function M.palette()
  if M._p then return M._p end
  local ok, p = pcall(dofile, vim.fn.expand("~/.config/theme/generated/gaussianvim-colors.lua"))
  M._p = vim.tbl_extend("force", DEFAULT, ok and type(p) == "table" and p or {})
  return M._p
end

-- blend two colors: mix(a, b, 0.2) = 80 % a + 20 % b
function M.mix(a, b, t)
  local function rgb(h) return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16) end
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local f = function(x, y) return math.floor(x + (y - x) * t + 0.5) end
  return ("#%02x%02x%02x"):format(f(r1, r2), f(g1, g2), f(b1, b2))
end

-- tokyonight's color names → Material roles + rice accents (syntax colors)
function M.on_colors(c)
  local p = M.palette()
  c.bg, c.bg_dark, c.bg_dark1 = p.bg, p.bg_low, p.bg_dim
  c.bg_float, c.bg_popup, c.bg_sidebar, c.bg_statusline = p.bg_float, p.bg_float, p.bg, p.bg
  c.bg_highlight, c.bg_visual, c.bg_search = p.bg_high, p.primary_container, p.secondary_container
  c.fg, c.fg_dark, c.fg_float, c.fg_sidebar = p.fg, p.fg_dim, p.fg, p.fg_dim
  c.fg_gutter, c.dark3, c.dark5, c.comment = p.outline_variant, p.outline_variant, p.outline, p.outline
  c.border, c.border_highlight = p.outline_variant, p.primary
  -- syntax: functions = primary, keywords = tertiary, types = cyan, strings = green
  c.blue, c.blue1, c.blue2, c.blue5, c.blue6 = p.primary, p.cyan, p.cyan_b, p.blue_b, p.cyan_b
  c.blue0, c.blue7 = p.primary_container, p.primary_container
  c.cyan, c.teal, c.green, c.green1, c.green2 = p.cyan, p.cyan_b, p.green, p.cyan, p.green_b
  c.magenta, c.magenta2, c.purple = p.tertiary, p.magenta_b, p.tertiary
  c.orange, c.yellow, c.red, c.red1 = p.yellow, p.yellow_b, p.red, p.red_b
  c.error, c.warning, c.info, c.hint = p.red, p.yellow, p.blue, p.cyan
  c.git = { add = p.green, change = p.blue, delete = p.red, ignore = p.outline }
end

-- Material styling for the whole UI
function M.on_highlights(hl)
  local p, mix = M.palette(), M.mix
  local card = { bg = p.bg_float, fg = p.fg }
  local card_border = { bg = p.bg, fg = p.outline_variant }      -- editor bg outside the rounded corners
  local title = { bg = p.primary, fg = p.on_primary, bold = true }

  -- editor
  hl.Normal = { bg = p.bg, fg = p.fg }
  hl.NormalNC = { bg = p.bg, fg = p.fg }
  hl.LineNr = { fg = p.outline_variant }
  hl.CursorLineNr = { fg = p.primary, bold = true }
  hl.CursorLine = { bg = p.bg_low }
  hl.Visual = { bg = p.primary_container }
  hl.Search = { bg = p.secondary_container, fg = p.on_secondary_container }
  hl.IncSearch = { bg = p.primary, fg = p.on_primary, bold = true }
  hl.CurSearch = hl.IncSearch
  hl.MatchParen = { bg = p.bg_highest, fg = p.primary, bold = true }
  hl.WinSeparator = { fg = p.bg_high }
  hl.EndOfBuffer = { fg = p.bg }
  hl.Folded = { bg = p.bg_low, fg = p.outline }
  hl.WinBar = { bg = p.bg, fg = p.fg_dim }
  hl.WinBarNC = { bg = p.bg, fg = p.outline }

  -- cards: every floating window, rounded, on a raised surface
  hl.NormalFloat = card
  hl.FloatBorder = card_border
  hl.FloatTitle = title
  hl.FloatFooter = { bg = p.bg, fg = p.outline }

  -- completion menu
  hl.Pmenu = { bg = p.bg_high, fg = p.fg }
  hl.PmenuSel = { bg = p.primary_container, fg = p.on_primary_container, bold = true }
  hl.PmenuSbar = { bg = p.bg_high }
  hl.PmenuThumb = { bg = p.outline_variant }
  hl.PmenuKind = { bg = p.bg_high, fg = p.tertiary }
  hl.PmenuExtra = { bg = p.bg_high, fg = p.outline }
  hl.BlinkCmpMenu = { bg = p.bg_high, fg = p.fg }
  hl.BlinkCmpMenuBorder = { bg = p.bg, fg = p.outline_variant }
  hl.BlinkCmpMenuSelection = hl.PmenuSel
  hl.BlinkCmpLabelMatch = { fg = p.primary, bold = true }
  hl.BlinkCmpKind = { fg = p.tertiary }
  hl.BlinkCmpDoc = card
  hl.BlinkCmpDocBorder = card_border
  hl.BlinkCmpDocSeparator = card_border
  hl.BlinkCmpSignatureHelp = card
  hl.BlinkCmpSignatureHelpBorder = card_border
  hl.BlinkCmpSignatureHelpActiveParameter = { bg = p.primary_container, fg = p.on_primary_container, bold = true }

  -- Space menu (which-key)
  hl.WhichKeyNormal = card
  hl.WhichKeyBorder = card_border
  hl.WhichKeyTitle = title
  hl.WhichKey = { fg = p.primary, bold = true }
  hl.WhichKeyGroup = { fg = p.tertiary }
  hl.WhichKeyDesc = { fg = p.fg }
  hl.WhichKeySeparator = { fg = p.outline_variant }
  hl.WhichKeyIcon = { fg = p.secondary }

  -- pickers, file tree, dashboard, notifications (snacks)
  hl.SnacksPicker = card
  hl.SnacksPickerBorder = card_border
  hl.SnacksPickerTitle = title
  hl.SnacksPickerInputBorder = { bg = p.bg, fg = p.primary }
  hl.SnacksPickerInputTitle = title
  hl.SnacksPickerPrompt = { fg = p.primary, bold = true }
  hl.SnacksPickerMatch = { fg = p.primary, bold = true }
  hl.SnacksPickerListCursorLine = { bg = p.primary_container }
  hl.SnacksPickerDir = { fg = p.outline }
  hl.SnacksPickerTotals = { fg = p.outline }
  hl.SnacksDashboardHeader = { fg = p.primary, bold = true }
  hl.SnacksDashboardKey = { fg = p.on_primary, bg = p.primary, bold = true }
  hl.SnacksDashboardIcon = { fg = p.tertiary }
  hl.SnacksDashboardDesc = { fg = p.fg }
  hl.SnacksDashboardFooter = { fg = p.outline }
  hl.SnacksInputNormal = card
  hl.SnacksInputBorder = { bg = p.bg, fg = p.primary }
  hl.SnacksInputTitle = title
  hl.SnacksNotifierInfo = card
  hl.SnacksNotifierBorderInfo = { bg = p.bg, fg = p.primary }
  hl.SnacksNotifierTitleInfo = { fg = p.primary, bold = true }
  hl.SnacksNotifierIconInfo = { fg = p.primary }
  hl.SnacksNotifierError = card
  hl.SnacksNotifierBorderError = { bg = p.bg, fg = p.error }
  hl.SnacksNotifierTitleError = { fg = p.error, bold = true }
  hl.SnacksNotifierIconError = { fg = p.error }
  hl.SnacksNotifierWarn = card
  hl.SnacksNotifierBorderWarn = { bg = p.bg, fg = p.yellow }
  hl.SnacksNotifierTitleWarn = { fg = p.yellow, bold = true }

  -- errors as Material chips: tinted background behind the message
  for name, col in pairs({ Error = p.red, Warn = p.yellow, Info = p.blue, Hint = p.cyan, Ok = p.green }) do
    hl["DiagnosticVirtualText" .. name] = { fg = col, bg = mix(p.bg, col, 0.12), italic = true }
    hl["Diagnostic" .. name] = { fg = col }
    hl["DiagnosticUnderline" .. name] = { undercurl = true, sp = col }
  end

  -- git marks in the gutter
  hl.GitSignsAdd = { fg = p.green }
  hl.GitSignsChange = { fg = p.blue }
  hl.GitSignsDelete = { fg = p.red }

  -- breadcrumbs
  hl.NavicText = { fg = p.fg_dim }
  hl.NavicSeparator = { fg = p.outline_variant }

  -- file tabs at the top (bufferline): selected tab = primary container
  hl.BufferLineFill = { bg = p.bg }

  -- GaussianVim's own menus and the Source Control card
  hl.GvMenu = { bg = p.bg_float, fg = p.fg }
  hl.GvMenuBorder = { bg = p.bg, fg = p.outline_variant }
  hl.GvMenuSel = { bg = p.primary_container, fg = p.on_primary_container, bold = true }
  hl.GvMenuIcon = { fg = p.primary }
  hl.GvMenuKey = { fg = p.outline }
  hl.GvMenuSep = { fg = p.bg_highest }
  hl.GvMenuDim = { fg = p.outline }
  hl.GvButton = { bg = p.bg_highest, fg = p.fg }
  hl.GvButtonPrimary = { bg = p.primary, fg = p.on_primary, bold = true }
  hl.GvSection = { fg = p.fg_dim, bold = true }
  hl.GvBadge = { bg = p.secondary_container, fg = p.on_secondary_container, bold = true }
  hl.GvAdded = { fg = p.green, bold = true }
  hl.GvModified = { fg = p.yellow, bold = true }
  hl.GvDeleted = { fg = p.red, bold = true }
  hl.GvUntracked = { fg = p.cyan, bold = true }
  hl.GvAction = { fg = p.outline }
  hl.GvPlaceholder = { fg = p.outline, italic = true }
  hl.GvHiddenCursor = { blend = 100, nocombine = true }

  -- run panel (F5): a slightly raised surface, status chips
  hl.GvPanel = { bg = p.bg_low, fg = p.fg }
  hl.GvRunBusy = { bg = p.primary_container, fg = p.on_primary_container, bold = true }
  hl.GvRunOk = { bg = mix(p.bg, p.green, 0.22), fg = p.green_b, bold = true }
  hl.GvRunFail = { bg = mix(p.bg, p.red, 0.25), fg = p.red_b, bold = true }
end

-- status line: a primary pill for the mode, raised surfaces next to it
function M.lualine_theme()
  local p = M.palette()
  local function mode(bg, fg)
    return {
      a = { bg = bg, fg = fg, gui = "bold" },
      b = { bg = p.bg_high, fg = p.fg },
      c = { bg = p.bg, fg = p.fg_dim },
      x = { bg = p.bg, fg = p.fg_dim },
      y = { bg = p.bg_high, fg = p.fg },
      z = { bg = bg, fg = fg, gui = "bold" },
    }
  end
  return {
    normal = mode(p.primary, p.on_primary),
    insert = mode(p.tertiary, p.on_tertiary),
    visual = mode(p.secondary, p.on_secondary),
    replace = mode(p.error, p.on_error),
    command = mode(p.green, p.bg),
    terminal = mode(p.cyan, p.bg),
    inactive = mode(p.bg_high, p.fg_dim),
  }
end

-- file tabs (bufferline): Material "chips"
function M.bufferline_highlights()
  local p = M.palette()
  local base = { bg = p.bg, fg = p.outline }
  local sel = { bg = p.primary_container, fg = p.on_primary_container, bold = true, italic = false }
  return {
    fill = { bg = p.bg },
    background = base, buffer_visible = base, close_button = base, close_button_visible = base,
    modified = base, modified_visible = base, duplicate = base, separator = { fg = p.bg, bg = p.bg },
    separator_visible = { fg = p.bg, bg = p.bg },
    buffer_selected = sel, close_button_selected = sel, modified_selected = sel, duplicate_selected = sel,
    separator_selected = { fg = p.bg, bg = p.primary_container },
    indicator_selected = { fg = p.primary, bg = p.primary_container },
    diagnostic_selected = sel, error_selected = sel, warning_selected = sel, info_selected = sel, hint_selected = sel,
    error_diagnostic_selected = { fg = p.red, bg = p.primary_container },
    warning_diagnostic_selected = { fg = p.yellow, bg = p.primary_container },
    tab_selected = sel, tab = base, tab_close = base,
    offset_separator = { fg = p.bg_high, bg = p.bg },
  }
end

return M
