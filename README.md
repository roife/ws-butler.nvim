# wsbutler.nvim

Whitespace butler for Neovim: tracks modified regions and trims trailing whitespace only where you touched, with optional end-of-buffer cleanup.

Neovim plugin inspired by [ws-butler](https://github.com/lewang/ws-butler).

## Features
- Trims trailing whitespace only in modified ranges on save with extmarks
- Optional end-of-buffer blank line trimming
- Opt-out via filetype or global toggle

## Requirements
- Neovim 0.9+

## Install
### lazy.nvim
```lua
{
  "roife/wsbutler.nvim",
  opts = {
    trim_eob = false,           -- trim blank lines at end-of-buffer
    ignore_filetypes = {},      -- e.g. { "markdown", "gitcommit" }
  },
}
```

### packer.nvim
```lua
use({
  "roife/wsbutler.nvim",
  config = function()
    require("wsbutler").setup({
      trim_eob = false,
      ignore_filetypes = {},
    })
  end,
})
```

## Usage
- With a plugin manager: load normally; `plugin/wsbutler.lua` calls `setup()` automatically unless `vim.g.wsbutler_disable` is set.
- Global opts shortcut (optional): set `vim.g.wsbutler_opts = { trim_eob = true }` before the plugin is loaded.
- Direct call: `require("wsbutler").setup()` anywhere in your config.

## Options
```lua
{
  trim_eob = false,           -- remove trailing blank lines at end-of-buffer
  ignore_filetypes = {},      -- list of filetypes to skip entirely
}
```

## Comparison to vim-strip-trailing-whitespace
- vim-strip-trailing-whitespace use a splay to track modified regions, wsbutler.nvim uses Neovim's built-in extmarks.

## License
MIT
