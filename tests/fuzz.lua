local helpers = require("tests.helpers")

local function parse_number(value, default)
  local num = tonumber(value)
  if num == nil then return default end
  return num
end

local function script_args()
  local args = {}
  local seen_script = false
  for _, value in ipairs(vim.v.argv) do
    if seen_script then
      args[#args + 1] = value
    elseif value:match("tests/fuzz%.lua$") then
      seen_script = true
    end
  end
  return args
end

local argv = script_args()
local rounds = parse_number(argv[1], 100)
local steps_per_round = parse_number(argv[2], 200)
local base_seed = parse_number(argv[3], os.time())

local cleanup = helpers.bootstrap({
  trim_eob = true,
  ignore_filetypes = {},
})

vim.opt.swapfile = false
vim.opt.undofile = false
vim.opt.eventignore = ""
vim.opt.hidden = true

local function rand(n)
  return math.random(n)
end

local alphabet = { "a", "b", "c", " ", "\t" }

local function random_text(max_len)
  local len = math.random(0, max_len)
  local chars = {}
  for i = 1, len do
    chars[i] = alphabet[rand(#alphabet)]
  end
  return table.concat(chars)
end

local function random_lines(max_lines, max_len)
  local count = math.random(0, max_lines)
  if count == 0 then return {} end

  local lines = {}
  for i = 1, count do
    lines[i] = random_text(max_len)
  end
  return lines
end

local function current_line(bufnr, row)
  return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
end

local function choose_row(bufnr, allow_eof)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local max_row = allow_eof and line_count or math.max(line_count - 1, 0)
  return math.random(0, max_row)
end

local function choose_col(line, allow_eol)
  local max_col = #line
  if not allow_eol and max_col > 0 then
    max_col = max_col - 1
  end
  return math.random(0, max_col)
end

local function op_set_lines(bufnr)
  local start_row = choose_row(bufnr, true)
  local end_row = math.random(start_row, vim.api.nvim_buf_line_count(bufnr))
  vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, random_lines(3, 12))
end

local function op_set_text(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then return end

  local start_row = choose_row(bufnr, false)
  local end_row = math.random(start_row, line_count - 1)
  local start_line = current_line(bufnr, start_row)
  local end_line = current_line(bufnr, end_row)
  local start_col = choose_col(start_line, true)
  local end_col = choose_col(end_line, true)

  if start_row == end_row and end_col < start_col then
    start_col, end_col = end_col, start_col
  end

  vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, random_lines(3, 10))
end

local function op_normal(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then return end

  local row = choose_row(bufnr, false)
  local line = current_line(bufnr, row)
  local col = choose_col(line, true)

  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_win_set_cursor(0, { row + 1, col })

  local commands = {
    "a ",
    "A ",
    "i\t",
    "o",
    "O",
    "x",
    "dd",
    "J",
  }
  vim.cmd("silent! normal! " .. commands[rand(#commands)])
end

local function assert_no_trailing_blank_tail(bufnr, context)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local last_nonblank = 0
  for i = #lines, 1, -1 do
    if lines[i]:find("%S") then
      last_nonblank = i
      break
    end
  end

  if last_nonblank == 0 then
    if #lines > 1 or lines[1] ~= "" then
      error(context .. ": expected an empty buffer after trimming blank-only content")
    end
    return
  end

  if last_nonblank < #lines then
    error(context .. ": trailing blank lines survived trim_eob")
  end
end

local function run_round(round_index)
  local seed = base_seed + round_index - 1
  math.randomseed(seed)

  local path = vim.fn.tempname() .. ".txt"
  helpers.write_file(path, random_lines(8, 20))
  if vim.fn.getfsize(path) < 0 then helpers.write_file(path, { "" }) end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()

  for step = 1, steps_per_round do
    local ops = { op_set_lines, op_set_text, op_normal }
    local ok, err = pcall(ops[rand(#ops)], bufnr)
    if not ok then
      error(string.format("seed=%d step=%d op_error=%s", seed, step, err))
    end

    if step % math.random(1, 5) == 0 then
      local write_ok, write_err = pcall(vim.cmd, "silent write")
      if not write_ok then
        error(string.format("seed=%d step=%d write_error=%s", seed, step, write_err))
      end
      assert_no_trailing_blank_tail(bufnr, string.format("seed=%d step=%d", seed, step))
    end
  end

  vim.cmd("bwipeout!")
  vim.fn.delete(path)
end

for round = 1, rounds do
  run_round(round)
  if round % 10 == 0 then
    print(string.format("completed round %d/%d", round, rounds))
  end
end

cleanup()
print(string.format("fuzz passed: rounds=%d steps=%d seed=%d", rounds, steps_per_round, base_seed))
vim.cmd("qall!")
