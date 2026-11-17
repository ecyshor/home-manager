{ config, pkgs, ... }:

{
  programs.nixvim = {
    plugins = {
      neogit.enable = true;
      gitsigns = {
        enable = true;
        settings.on_attach.__raw = ''
          function(bufnr)
            local gs = require('gitsigns')
            local function map(mode, l, r, desc)
              vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
            end

            map('n', ']h', function()
              if vim.wo.diff then
                vim.cmd.normal({ ']c', bang = true })
              else
                gs.nav_hunk('next')
              end
            end, 'Next hunk')
            map('n', '[h', function()
              if vim.wo.diff then
                vim.cmd.normal({ '[c', bang = true })
              else
                gs.nav_hunk('prev')
              end
            end, 'Previous hunk')

            map('n', '<leader>gs', gs.stage_hunk, 'Stage/unstage hunk')
            map('n', '<leader>gr', gs.reset_hunk, 'Reset hunk')
            map('v', '<leader>gs', function()
              gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
            end, 'Stage/unstage selected lines')
            map('v', '<leader>gr', function()
              gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
            end, 'Reset selected lines')
            map('n', '<leader>gS', gs.stage_buffer, 'Stage buffer')
            map('n', '<leader>gR', gs.reset_buffer, 'Reset buffer')
            map('n', '<leader>gp', gs.preview_hunk, 'Preview hunk')
            map('n', '<leader>gb', function() gs.blame_line({ full = true }) end, 'Blame line')
            map('n', '<leader>gB', gs.toggle_current_line_blame, 'Toggle inline blame')
            map({ 'o', 'x' }, 'ih', gs.select_hunk, 'Select hunk')
          end
        '';
      };
      diffview.enable = true;
    };
    keymaps = [
      {
        action = "<cmd>DiffviewOpen<CR>";
        key = "<leader>gd";
        mode = "n";
        options.desc = "Diffview: open";
      }
      {
        action = "<cmd>DiffviewFileHistory %<CR>";
        key = "<leader>gh";
        mode = "n";
        options.desc = "Diffview: current file history";
      }
      {
        action = "<cmd>DiffviewFileHistory<CR>";
        key = "<leader>gH";
        mode = "n";
        options.desc = "Diffview: repo history";
      }
      {
        action = "<cmd>DiffviewClose<CR>";
        key = "<leader>gq";
        mode = "n";
        options.desc = "Diffview: close";
      }
      {
        action = "<cmd>Neogit<CR>";
        key = "<leader>gg";
        mode = "n";
        options = {
          desc = "Show Neogit window.";
        };
      }
    ];
  };
}
