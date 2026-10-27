{ pkgs, ... }: {

  # Claude Code (`claude`) in a toggleable floating terminal.
  # Complements the Avante ACP integration by allowing direct access to the
  # interactive Claude Code TUI. The underlying job survives closing the window,
  # so a conversation can be hidden with <leader>cc and resumed later.
  programs.nixvim.extraConfigLua = ''
    local claude = { win = nil, buf = nil }

    local function claude_running(buf)
      local job = vim.b[buf].terminal_job_id
      -- jobwait returns a list of exit codes; -1 means the job is still alive
      return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
    end

    local function claude_open()
      local fresh = claude.buf == nil
        or not vim.api.nvim_buf_is_valid(claude.buf)
        or not claude_running(claude.buf)
      if fresh then
        claude.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[claude.buf].buflisted = false
      end

      local width = math.floor(vim.o.columns * 0.85)
      local height = math.floor(vim.o.lines * 0.85)
      claude.win = vim.api.nvim_open_win(claude.buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        border = "rounded",
      })
      vim.wo[claude.win].winbar = " Claude Code (claude)"

      if fresh then
        vim.fn.termopen("${pkgs.claude-code}/bin/claude")
      end
      vim.cmd("startinsert")
    end

    local function claude_toggle()
      if claude.win ~= nil and vim.api.nvim_win_is_valid(claude.win) then
        vim.api.nvim_win_close(claude.win, true)
        claude.win = nil
      else
        claude_open()
      end
    end

    vim.keymap.set("n", "<leader>cc", claude_toggle, { desc = "Toggle Claude Code floating terminal" })
  '';
}
