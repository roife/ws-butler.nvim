local helpers = require("tests.helpers")

helpers.bootstrap({}, function(fn)
  fn()
end)

local path = vim.fn.tempname()
helpers.write_file(path, { "abc", "def   " })

vim.cmd.edit(path)
vim.api.nvim_buf_set_lines(0, 0, 2, false, { "ABC", "DEF   " })
vim.cmd.write()

helpers.assert_lines(
  { "ABC", "DEF" },
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  "ranges ending at EOF should include the last line when trimming"
)
