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

local function should_ignore(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return true
  end

  if filetype_ignored(bufnr) then
    return true
  end

  if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then
    return true
  end

  if vim.api.nvim_get_option_value("readonly", { buf = bufnr }) then
    return true
  end

  if not vim.api.nvim_get_option_value("modifiable", { buf = bufnr }) then
    return true
  end

  return false
end

local function mark_changed_range(bufnr, start_row, old_end_row, new_end_row)
  if suspend[bufnr] or start_row == new_end_row then
    return
  end

  -- If the change happens in the same line, do not add extmark
  if start_row + 1 == old_end_row and old_end_row == new_end_row then
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, { start_row, 0 }, { old_end_row, 0 }, {})
    if #marks > 0 then
      return
    end
  end

  vim.api.nvim_buf_set_extmark(bufnr, NS, start_row, 0, {
    end_row = old_end_row,
    end_col = 0,
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
    if start_row == end_row then
      goto continue
    end

    if not cur_start then
      cur_start, cur_end = start_row, end_row
      goto continue
    end

    if start_row <= cur_end then
      if end_row > cur_end then
        cur_end = end_row
      end
      goto continue
    end

    merged[#merged + 1] = { cur_start, cur_end }
    cur_start, cur_end = start_row, end_row
    ::continue::
  end

  if cur_start then
    merged[#merged + 1] = { cur_start, cur_end }
  end
  return merged
end

local TRAIL_WS_PATTERN = "%s+$"

local function trim_trailing_whitespace_in_ranges(bufnr, ranges)
  if #ranges == 0 then
    return
  end

  for _, range in ipairs(ranges) do
    local start_row = range[1]
    local end_row = range[2]

    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
    local changed = false

    for i, line in ipairs(lines) do
      local s = line:find(TRAIL_WS_PATTERN)
      if s then
        lines[i] = line:sub(1, s - 1)
        changed = true
      end
    end

    if changed then
      vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, lines)
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
  if vim.api.nvim_win_get_buf(win) ~= bufnr then
    return
  end

  vim.b[bufnr].wsbutler_last_cursor = vim.api.nvim_win_get_cursor(win)
end

local function restore_cursor(bufnr)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then
    return
  end

  local pos = vim.b[bufnr].wsbutler_last_cursor
  if not pos then
    return
  end

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
      if attached[bufnr] or should_ignore(bufnr) then
        return
      end

      attached[bufnr] = true

      vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function(_, buf, _, first, old_last, new_last)
          if should_ignore(buf) then
            return
          end
          mark_changed_range(buf, first, old_last, new_last)
        end,
        on_detach = function(_, buf)
          attached[buf] = nil
        end,
      })
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePre", {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if should_ignore(bufnr) then
        return
      end

      save_cursor(bufnr)

      local ranges = get_merged_modified_ranges(bufnr)

      suspend[bufnr] = true
      trim_trailing_whitespace_in_ranges(bufnr, ranges)
      if config.trim_eob then
        trim_eob_blank_lines(bufnr)
      end
      suspend[bufnr] = nil

      vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug,
    callback = function(args)
      local bufnr = args.buf
      if should_ignore(bufnr) then
        return
      end

      restore_cursor(bufnr)
    end,
  })
end

return M
