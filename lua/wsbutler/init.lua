local M = {}

local defaults = {
  trim_eob = false,
  ignore_filetypes = {},
}

local config = vim.tbl_deep_extend("force", {}, defaults)

local NS = vim.api.nvim_create_namespace("wsbutler.nvim")

local attached = {}
local suspend = {}

local function filetype_ignored(bufnr)
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  return ft ~= "" and vim.tbl_contains(config.ignore_filetypes, ft)
end

local ignored_events = { "all", "TextChanged", "TextChangedI", "TextChangedP" }
local function should_ignore(bufnr)
  if suspend[bufnr] then return true end

  if not vim.api.nvim_buf_is_loaded(bufnr) then return true end

  local ei = vim.o.eventignore
  if ei and ei ~= "" then
    for _, ev in ipairs(ignored_events) do
      if ei:find(ev, 1, true) ~= nil then return true end
    end
  end

  if filetype_ignored(bufnr) then return true end

  if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then return true end

  if vim.api.nvim_get_option_value("readonly", { buf = bufnr }) then return true end

  if not vim.api.nvim_get_option_value("modifiable", { buf = bufnr }) then return true end

  return false
end

local function mark_changed_range(bufnr, start_row, start_col, new_end_row, new_end_col)
  local new_end_pos = { new_end_row, new_end_col }

  local start_line_count = #vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
  if start_col == start_line_count then start_row = start_row + 1 end

  local num_lines = vim.api.nvim_buf_line_count(bufnr)
  if new_end_row == num_lines - 1 then
    local marks = vim.api.nvim_buf_get_extmarks(
      bufnr,
      NS,
      { new_end_row, 0 },
      new_end_pos,
      { details = true, limit = 1 }
    )
    if #marks > 0 then return end
    new_end_col = #vim.api.nvim_buf_get_lines(0, -2, -1, false)[1]
  else
    local marks = vim.api.nvim_buf_get_extmarks(
      bufnr,
      NS,
      new_end_pos,
      new_end_pos,
      { details = true, overlap = true, limit = 1 }
    )
    if #marks > 0 then return end
    if new_end_col ~= 0 then new_end_row = new_end_row + 1 end
    new_end_col = 0
  end

  vim.api.nvim_buf_set_extmark(bufnr, NS, start_row, 0, {
    end_row = new_end_row,
    end_col = new_end_col,
    right_gravity = false,
    end_right_gravity = true,
  })
end

local function get_merged_modified_ranges(bufnr)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, { details = true })

  local merged = {}
  local cur_start, cur_end

  for _, mark in ipairs(marks) do
    local start_row = mark[2]
    local end_row = mark[4].end_row

    if not cur_start then
      cur_start, cur_end = start_row, end_row
      goto continue
    end

    if start_row <= cur_end then
      if end_row > cur_end then cur_end = end_row end
      goto continue
    end

    merged[#merged + 1] = { cur_start, cur_end }
    cur_start, cur_end = start_row, end_row
    ::continue::
  end

  if cur_start then merged[#merged + 1] = { cur_start, cur_end } end
  return merged
end

local TRAIL_WS_PATTERN = "%s+$"

local function trim_trailing_whitespace_in_ranges(bufnr, ranges)
  if not ranges or #ranges == 0 then return end
  local num_lines = vim.api.nvim_buf_line_count(bufnr)

  for _, range in ipairs(ranges) do
    local start_row = range[1]
    local end_row = range[2]
    if start_row == num_lines - 1 then end_row = -1 end

    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)

    for i, line in ipairs(lines) do
      local s = line:find(TRAIL_WS_PATTERN)
      if s then
        local new_line = line:sub(1, s - 1)
        local row = start_row + i - 1

        vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
      end
    end
  end
end

local function trim_eob_blank_lines(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local last_nonblank = 0
  for i = #lines, 1, -1 do
    if lines[i]:find("%S") then
      last_nonblank = i
      break
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, last_nonblank + 1, -1, false, {})
end

local function save_cursor(bufnr)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then return end

  vim.b[bufnr].wsbutler_last_cursor = vim.api.nvim_win_get_cursor(win)
end

local function restore_cursor(bufnr)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then return end

  local pos = vim.b[bufnr].wsbutler_last_cursor
  if not pos then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  pos[1] = math.min(pos[1], line_count)

  pcall(vim.api.nvim_win_set_cursor, win, pos)
  vim.b[bufnr].wsbutler_last_cursor = nil
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  config.ignore_filetypes = config.ignore_filetypes or {}

  local aug = vim.api.nvim_create_augroup("wsbutler.nvim", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if attached[bufnr] or should_ignore(bufnr) then return end

      attached[bufnr] = true

      vim.api.nvim_buf_attach(bufnr, false, {
        on_bytes = function(
          _,
          buf,
          _,
          start_row,
          start_col,
          _,
          _,
          _,
          _,
          new_end_row,
          new_end_col,
          _
        )
          if should_ignore(buf) then return end
          vim.schedule(function()
            if new_end_row == 0 then new_end_col = start_col + new_end_col end
            new_end_row = start_row + new_end_row
            if start_row == new_end_row and start_col == new_end_col then return end

            mark_changed_range(buf, start_row, start_col, new_end_row, new_end_col)
          end)
        end,
        on_detach = function(_, buf) attached[buf] = nil end,
      })
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePre", {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if should_ignore(bufnr) then return end

      save_cursor(bufnr)

      local ranges = get_merged_modified_ranges(bufnr)

      suspend[bufnr] = true
      trim_trailing_whitespace_in_ranges(bufnr, ranges)
      if config.trim_eob then trim_eob_blank_lines(bufnr) end
      suspend[bufnr] = nil

      vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if should_ignore(bufnr) then return end

      restore_cursor(bufnr)
    end,
  })
end

return M

