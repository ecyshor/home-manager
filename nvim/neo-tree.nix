{
  programs.nixvim = {
    plugins = {
      neo-tree = {
        enable = true;

        # https://github.com/nvim-neo-tree/neo-tree.nvim/blob/main/lua/neo-tree/defaults.lua
        settings = {

          window = {
            mappings = {
              "g" = "grep_in_directory";
            };
          };

          source_selector = {
            winbar = true;
          };
          # Define the custom command
          commands = {
            grep_in_directory = {
              __raw = ''
              function(state)
                local node = state.tree:get_node()
                local path = node.type == 'directory' and node.path or vim.fn.fnamemodify(node.path, ":h")

                -- Ensure telescope is available
                local has_telescope, builtin = pcall(require, "telescope.builtin")
                if not has_telescope then
                  print("Telescope not found")
                  return
                end

                builtin.live_grep({
                  search_dirs = { path },
                  prompt_title = "Grep in: " .. vim.fn.fnamemodify(path, ":t"),
                })
              end
              '';
            };
          };
        };
      };
    };

    keymaps = [
      {
        action = "<cmd>Neotree toggle<CR>";
        key = "<C-n>";
        mode = "n";
        options = {
          desc = "Toggle Tree View.";
        };
      }
      {
        action = "<cmd>Neotree reveal<CR>";
        key = "<leader>n.";
        mode = "n";
        options = {
          desc = "Go to current file in neotree view.";
        };
      }
      {
        action = "<C-w><Left>";
        key = "<C-h>";
        mode = "n";
        options = {
          desc = "Switch to the left buffer.";
        };
      }
      {
        action = "<C-w><Right>";
        key = "<C-l>";
        mode = "n";
        options = {
          desc = "Switch to the right buffer.";
        };
      }
    ];
  };
}
