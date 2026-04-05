local M = {}

local function fmt_lines(lines)
  local quoted = vim.tbl_map(function(line)
    return string.format("%q", line)
  end, lines)
  return "[" .. table.concat(quoted, ", ") .. "]"
end

function M.bootstrap(opts, schedule)
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  vim.opt.swapfile = false
  vim.opt.shada = ""
  package.path = table.concat({
    cwd .. "/lua/?.lua",
    cwd .. "/lua/?/init.lua",
    package.path,
  }, ";")

  local original_schedule = vim.schedule
  if schedule then vim.schedule = schedule end

  require("wsbutler").setup(opts or {})

  return function()
    vim.schedule = original_schedule
  end
end

function M.write_file(path, lines)
  local file = assert(io.open(path, "w"))
  file:write(table.concat(lines, "\n"))
  file:close()
end

function M.assert_lines(expected, actual, context)
  if #expected ~= #actual then
    error(string.format(
      "%s: expected %s, got %s",
      context,
      fmt_lines(expected),
      fmt_lines(actual)
    ))
  end

  for i, expected_line in ipairs(expected) do
    if actual[i] ~= expected_line then
      error(string.format(
        "%s: expected %s, got %s",
        context,
        fmt_lines(expected),
        fmt_lines(actual)
      ))
    end
  end
end

return M
