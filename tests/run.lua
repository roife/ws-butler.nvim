local wsbutler = require("wsbutler")

local failures = {}

local function flush(ms)
  vim.wait(ms or 20, function()
    return false
  end)
end

local function same_lines(actual, expected)
  return vim.deep_equal(actual, expected)
end

local function expect_lines(label, actual, expected)
  if same_lines(actual, expected) then
    return
  end

  failures[#failures + 1] = {
    label = label,
    expected = expected,
    actual = actual,
  }
end

local function with_file(initial_lines, fn)
  local path = vim.fn.tempname() .. ".txt"
  vim.fn.writefile(initial_lines, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))

  local ok, err = pcall(fn, vim.api.nvim_get_current_buf(), path)

  vim.cmd("bwipeout!")
  vim.fn.delete(path)

  if not ok then
    error(err)
  end
end

local function current_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function run_case(name, opts, fn)
  wsbutler.setup(opts)
  with_file(fn.initial_lines, function(bufnr, path)
    fn.run(bufnr, path)
    flush(50)
  end)
  print("ran: " .. name)
end

run_case("issue-1-stale-on-bytes-coordinates", { trim_eob = false }, {
  initial_lines = { "keep", "target  " },
  run = function(bufnr)
    vim.api.nvim_buf_set_text(bufnr, 1, 0, 1, 0, { "!" })
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new" })
    flush(50)

    vim.cmd("silent write")

    expect_lines(
      "issue-1-stale-on-bytes-coordinates",
      current_lines(bufnr),
      { "new", "keep", "!target" }
    )
  end,
})

run_case("issue-2-trim-eob-off-by-one", { trim_eob = true }, {
  initial_lines = { "alpha", "", "", "" },
  run = function(bufnr)
    vim.cmd("silent write")

    expect_lines(
      "issue-2-trim-eob-off-by-one",
      current_lines(bufnr),
      { "alpha" }
    )
  end,
})

run_case("issue-3-multiline-range-ending-at-eof", { trim_eob = false }, {
  initial_lines = { "foo", "bar  " },
  run = function(bufnr)
    vim.api.nvim_buf_set_text(bufnr, 0, 0, 1, 3, { "FOO", "BAR  " })
    flush(50)

    vim.cmd("silent write")

    expect_lines(
      "issue-3-multiline-range-ending-at-eof",
      current_lines(bufnr),
      { "FOO", "BAR" }
    )
  end,
})

if #failures > 0 then
  for _, failure in ipairs(failures) do
    io.stderr:write("FAIL: " .. failure.label .. "\n")
    io.stderr:write("expected: " .. vim.inspect(failure.expected) .. "\n")
    io.stderr:write("actual:   " .. vim.inspect(failure.actual) .. "\n")
  end

  vim.cmd("cq")
end

print("all tests passed")
vim.cmd("qall!")
