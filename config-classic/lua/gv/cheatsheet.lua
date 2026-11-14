-- Space ? : search the cheat sheet (cheatsheet.tsv in the config folder).
-- Type any part of what you want to do ("delete line", "replace", "split").
local M = {}

M.file = vim.fn.stdpath("config") .. "/cheatsheet.tsv"

function M.items()
  local items = {}
  for line in io.lines(M.file) do
    local cat, keys, rest = line:match("^([^#\t][^\t]*)\t([^\t]+)\t(.+)$")
    if cat then
      local desc, words = rest:match("^([^\t]*)\t(.*)$")   -- 4th column: extra search words
      desc = desc or rest
      items[#items + 1] = { text = table.concat({ cat, keys, desc, words or "" }, " "), cat = cat, keys = keys, desc = desc }
    end
  end
  return items
end

function M.open()
  Snacks.picker.pick({
    title = "Vim cheat sheet",
    items = M.items(),
    layout = { preset = "select", layout = { width = 0.75, min_width = 96, height = 0.7 } },
    format = function(item)
      return {
        { ("%-9s"):format(item.cat), "Comment" },
        { ("%-26s"):format(item.keys), "Special" },
        { item.desc },
      }
    end,
    confirm = function(picker, item)    -- Enter shows it in a notification and closes
      picker:close()
      if item then vim.notify(item.keys .. "   " .. item.desc, vim.log.levels.INFO, { title = "Cheat sheet" }) end
    end,
  })
end

return M
