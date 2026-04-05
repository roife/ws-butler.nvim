local helpers = require("tests.helpers")

helpers.bootstrap({ trim_eob = true }, function(fn)
  fn()
end)

local path = vim.fn.tempname()
helpers.write_file(path, { "alpha", "", "" })

vim.cmd.edit(path)
vim.cmd.write()

helpers.assert_lines(
  { "alpha" },
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  "trim_eob should remove every trailing blank line"
)
