-- The dock: hidden panels wait as buttons at the right end of the status line
-- (the bar at the bottom), so nothing you hide gets lost.
--
--   Ctrl+q        in a panel (Claude, a Stack Exchange answer, docs, wiki, a
--                 floating terminal, ...): hide it; it shows up in the dock
--   click it      in the dock: bring it back where it was, at the size it had
--   Ctrl+q        in the editor: bring back the panel hidden last
--                 (with nothing hidden: the quickfix list, as before)
--   Space u h     pick a hidden panel from a list
local M = {}

M.items = {}        -- hidden panels: { key, icon, name, restore = fn, valid = fn? }
M.providers = {}    -- functions returning a dock item or nil (panels that hide themselves, e.g. Claude)

local function refresh()
  pcall(function() require("lualine").refresh({ place = { "statusline" } }) end)
  vim.cmd.redrawstatus()
end
M.refresh = refresh

function M.add(item)
  M.remove(item.key, true)
  table.insert(M.items, item)
  refresh()
end

function M.remove(key, quiet)
  for i = #M.items, 1, -1 do
    if M.items[i].key == key then table.remove(M.items, i) end
  end
  if not quiet then refresh() end
end

function M.provide(fn) table.insert(M.providers, fn) end

-- everything waiting in the dock, oldest first
function M.list()
  local out = {}
  for i = #M.items, 1, -1 do
    local it = M.items[i]
    if it.valid and not it.valid() then table.remove(M.items, i) end
  end
  for _, it in ipairs(M.items) do out[#out + 1] = it end
  for _, p in ipairs(M.providers) do
    local ok, it = pcall(p)
    if ok and it then out[#out + 1] = it end
  end
  return out
end

function M.restore(item)
  if not item then return end
  M.remove(item.key, true)
  local ok, err = pcall(item.restore)
  if not ok then vim.notify("Couldn't bring it back: " .. tostring(err), vim.log.levels.WARN, { title = "Dock" }) end
  refresh()
end

-- Ctrl+q in the editor: the panel hidden last
function M.restore_last()
  local l = M.list()
  if #l == 0 then return false end
  M.restore(l[#l])
  return true
end

function M.pick()
  local l = M.list()
  if #l == 0 then return vim.notify("Nothing is hidden", vim.log.levels.INFO, { title = "Dock" }) end
  vim.ui.select(l, { prompt = "Bring back", format_item = function(it) return (it.icon or "") .. " " .. it.name end },
    function(it) if it then M.restore(it) end end)
end

-- the buttons in the status line (clickable: %N@v:lua.GvDockClick@ ... %X)
_G.GvDockClick = function(idx) M.restore(M.list()[idx]) end

function M.status()
  local l = M.list()
  if #l == 0 then return "" end
  local parts = {}
  for i, it in ipairs(l) do
    local name = it.name:gsub("%%", "%%%%")
    if #name > 22 then name = name:sub(1, 21) .. "…" end
    parts[#parts + 1] = ("%%%d@v:lua.GvDockClick@ %s %s \u{f0143} %%X"):format(i, it.icon or "\u{f05b7}", name)
  end
  return table.concat(parts, "│")
end

function M.visible() return #M.list() > 0 end

return M
