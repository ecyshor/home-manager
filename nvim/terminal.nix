{ pkgs, ... }: {

  # Toggleable general shell terminals:
  # - <leader>tf: floating terminal
  # - <leader>tt / <C-/>: bottom horizontal split terminal
  # Underlying shell jobs survive closing the window so they can be toggled back open.
  programs.nixvim.extraConfigLua = ''
    local float_term = { win = nil, buf = nil }
    local split_term = { win = nil, buf = nil }

    local function term_running(buf)
      local job = vim.b[buf].terminal_job_id
      return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
    end

    local function ensure_term_buf(state)
      local fresh = state.buf == nil
        or not vim.api.nvim_buf_is_valid(state.buf)
        or not term_running(state.buf)
      if fresh then
        state.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[state.buf].buflisted = false
      end
      return fresh
    end

    local function toggle_float_term()
      if float_term.win ~= nil and vim.api.nvim_win_is_valid(float_term.win) then
        vim.api.nvim_win_close(float_term.win, true)
        float_term.win = nil
        return
      end

      local fresh = ensure_term_buf(float_term)
      local width = math.floor(vim.o.columns * 0.85)
      local height = math.floor(vim.o.lines * 0.85)
      float_term.win = vim.api.nvim_open_win(float_term.buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        border = "rounded",
      })
      vim.wo[float_term.win].winbar = " Terminal (float)"

      if fresh then
        vim.fn.termopen("${pkgs.fish}/bin/fish")
      end
      vim.cmd("startinsert")
    end

    local function toggle_split_term()
      if split_term.win ~= nil and vim.api.nvim_win_is_valid(split_term.win) then
        vim.api.nvim_win_close(split_term.win, true)
        split_term.win = nil
        return
      end

      local fresh = ensure_term_buf(split_term)
      local height = math.max(10, math.floor(vim.o.lines * 0.3))
      vim.cmd("botright " .. height .. "split")
      split_term.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(split_term.win, split_term.buf)
      vim.wo[split_term.win].winfixheight = true

      if fresh then
        vim.fn.termopen("${pkgs.fish}/bin/fish")
      end
      vim.cmd("startinsert")
    end

    vim.keymap.set("n", "<leader>tf", toggle_float_term, { desc = "Toggle floating terminal" })
    vim.keymap.set("n", "<leader>tt", toggle_split_term, { desc = "Toggle bottom split terminal" })
    vim.keymap.set({ "n", "t" }, "<C-/>", toggle_split_term, { desc = "Toggle bottom split terminal" })
    vim.keymap.set({ "n", "t" }, "<C-_>", toggle_split_term, { desc = "Toggle bottom split terminal" })
  '';
}
