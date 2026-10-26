{ pkgs, ... }: {

  # Google Antigravity (`agy`) in a toggleable floating terminal.
  # The CLI has no ACP mode, so it runs as an interactive terminal instead
  # of an avante agent. The underlying job survives closing the window, so
  # a conversation can be hidden with <leader>ag and resumed later.
  programs.nixvim.extraConfigLua = ''
    local agy = { win = nil, buf = nil }

    local function agy_running(buf)
      local job = vim.b[buf].terminal_job_id
      -- jobwait returns a list of exit codes; -1 means the job is still alive
      return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
    end

    local function agy_open()
      local fresh = agy.buf == nil
        or not vim.api.nvim_buf_is_valid(agy.buf)
        or not agy_running(agy.buf)
      if fresh then
        agy.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[agy.buf].buflisted = false
      end

      local width = math.floor(vim.o.columns * 0.85)
      local height = math.floor(vim.o.lines * 0.85)
      agy.win = vim.api.nvim_open_win(agy.buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        border = "rounded",
      })
      vim.wo[agy.win].winbar = " Antigravity (agy)"

      if fresh then
        vim.fn.termopen("${pkgs.antigravity-cli}/bin/agy")
      end
      vim.cmd("startinsert")
    end

    local function agy_toggle()
      if agy.win ~= nil and vim.api.nvim_win_is_valid(agy.win) then
        vim.api.nvim_win_close(agy.win, true)
        agy.win = nil
      else
        agy_open()
      end
    end

    vim.keymap.set("n", "<leader>ag", agy_toggle, { desc = "Toggle agy (Antigravity) floating terminal" })
  '';
}
