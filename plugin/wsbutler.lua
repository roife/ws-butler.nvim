if vim.g.wsbutler_disable then return end

local ok, wsbutler = pcall(require, "wsbutler")
if not ok then return end

wsbutler.setup(vim.g.wsbutler_opts)
