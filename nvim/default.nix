{ inputs, lib, config, pkgs, ... }: {

  imports = [
    ./neo-tree.nix
    ./neogit.nix
    ./nvim-cmp.nix
  ];
  
  programs.nixvim = {
    enable = true;
    viAlias = true;
    vimAlias = true;

    # Theme
    colorschemes.tokyonight.enable = true;

    # Settings
    opts = {
      expandtab = true;
      shiftwidth = 2;
      smartindent = true;
      tabstop = 2;
      number = true;
      relativenumber = true; # Show relative line numbers
      clipboard = "unnamedplus";
    };

    # Keymaps
    globals = {
      mapleader = " ";
    };

    plugins = {

      # UI
      lualine.enable = true;
      bufferline.enable = true;
      web-devicons.enable = true;
      treesitter = {
        enable = true;
          settings = {
            indent = {
              enable = true;
            };
            auto_install = true;
            ensureInstalled = [
              "javascript"
              "nix"
              "tsx"
              "typescript"
              "vim"
              "vimdoc"
            ];
          };
      };
      which-key = {
        enable = true;
      };
      noice = {
        # WARNING: This is considered experimental feature, but provides nice UX
        enable = true;
        settings.presets = {
          bottom_search = true;
          command_palette = true;
          long_message_to_split = true;
          #inc_rename = false;
          #lsp_doc_border = false;
        };
      };
      telescope = {
        enable = true;
        settings.defaults = {
          file_ignore_patterns = [
              "^.git/"
              "^.mypy_cache/"
              "^__pycache__/"
              "^output/"
              "^data/"
              "%.ipynb"
            ];
        };
        keymaps = {
          "<leader>b" = {
            options = {
              desc = "buffer finder";
            };
            action = "buffers";
          };
          "<leader>ff" = {
            options = {
              desc = "file finder";
            };
            action = "find_files";
          };
          "<leader>fg" = {
            options = {
              desc = "find via grep";
            };
            action = "live_grep";

          };
          "<leader>fr" = {
            options = {
              desc = "resume last search";
            };
            action = "resume";
          };
          "<leader>fd" = {
            action = "diagnostics";
            options.desc = "View diagnostics";
          };

        };
        extensions = {
          fzf-native.enable = true;
          live-grep-args = {
            enable = true;
            settings = {
              vimgrep_arguments = [
                "rg"
                "--follow"
                "--hidden"
                "--with-filename"
                "--line-number"
                "--smart-case"
                # Exclude some patterns from search
                "--glob=!**/.git/*"
                "--glob=!**/.idea/*"
                "--glob=!**/.vscode/*"
                "--glob=!**/build/*"
                "--glob=!**/dist/*"
                "--glob=!**/yarn.lock"
                "--glob=!**/package-lock.json"
              ];
              addition_args = ["--hidden"];
            };
          };
        };
      };

      # Dev
      lsp = {
        enable = true;
        servers = {
          hls = {
            enable = true;
            installGhc = true;
          };
          marksman.enable = true;
          nil_ls.enable = true;
          rust_analyzer = {
            enable = true;
            installCargo = false;
            installRustc = false;
          };
        };
      };
    };

    
  keymaps = [
        {
          mode = "n";
          key = "<leader>fF";
          action.__raw = ''
            function()
              vim.cmd('Telescope find_files hidden=true no_ignore=true')
            end
          '';
          options = {
            desc = "Find all files";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>f/";
          action.__raw = ''
            function()
              vim.cmd('Telescope live_grep grep_open_files=true')
            end
          '';
          options = {
            desc = "Find words in all open buffers";
            silent = true;
          };
        }
   ];
  };
}
