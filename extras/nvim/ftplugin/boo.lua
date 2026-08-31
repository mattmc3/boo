local bo = vim.bo[vim.api.nvim_get_current_buf()]
bo.commentstring = "# %s"
bo.comments = ":#,://"
bo.expandtab = false
bo.tabstop = 4
bo.shiftwidth = 4
bo.softtabstop = 0
