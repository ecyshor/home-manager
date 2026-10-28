{ pkgs, ... }: {

  # Claude Code (`claude`) floating terminal (<leader>cc), interactive session
  # switcher (<leader>cs), and live Lualine status + quota indicator.
  programs.nixvim.plugins.lualine.settings.sections.lualine_x = [
    {
      __raw = ''
        (function()
          local cached_status = ""
          local last_check = 0
          return {
            function()
              local now = vim.uv.hrtime() / 1e9
              if now - last_check >= 5 then
                last_check = now
                vim.system({ "claude-sessions", "--status-bar" }, { text = true }, function(obj)
                  if obj.code == 0 and obj.stdout then
                    cached_status = obj.stdout:gsub("%s+$", ""):gsub("%%", "%%%%")
                  end
                end)
              end
              return cached_status
            end,
          }
        end)()
      '';
    }
    "encoding"
    "fileformat"
    "filetype"
  ];

  programs.nixvim.extraConfigLua = ''
    local claude = { win = nil, buf = nil }

    local function claude_running(buf)
      local job = vim.b[buf].terminal_job_id
      -- jobwait returns a list of exit codes; -1 means the job is still alive
      return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
    end

    local function open_float_win(buf, title)
      local width = math.floor(vim.o.columns * 0.85)
      local height = math.floor(vim.o.lines * 0.85)
      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        border = "rounded",
      })
      vim.wo[win].winbar = title
      return win
    end

    local function claude_open()
      local fresh = claude.buf == nil
        or not vim.api.nvim_buf_is_valid(claude.buf)
        or not claude_running(claude.buf)
      if fresh then
        claude.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[claude.buf].buflisted = false
      end

      claude.win = open_float_win(claude.buf, " Claude Code (claude)")

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

    local function claude_sessions_picker()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buflisted = false
      local win = open_float_win(buf, " Claude Code Sessions (Active / Idle)")
      vim.fn.termopen("claude-sessions", {
        on_exit = function()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end,
      })
      vim.cmd("startinsert")
    end

    vim.keymap.set("n", "<leader>cc", claude_toggle, { desc = "Toggle Claude Code floating terminal" })
    vim.keymap.set("n", "<leader>cs", claude_sessions_picker, { desc = "Claude Code sessions overview" })
  '';
}
