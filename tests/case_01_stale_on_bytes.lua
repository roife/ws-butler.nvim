local helpers = require("tests.helpers")

local queued = {}
local restore_schedule = helpers.bootstrap({}, function(fn)
  queued[#queued + 1] = fn
end)

local path = vim.fn.tempname()
helpers.write_file(path, { "a", "b   " })

vim.cmd.edit(path)

vim.api.nvim_buf_set_text(0, 1, 1, 1, 1, { "x" })
vim.api.nvim_buf_set_lines(0, 0, 0, false, { "zzz" })

for _, callback in ipairs(queued) do
  callback()
end

restore_schedule()

vim.cmd.write()

helpers.assert_lines(
  { "zzz", "a", "bx" },
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  "stale on_bytes callbacks should still trim the moved last line"
)
