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
      treesitter = {
        enable = true;
          settings = {
            indent = true;
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
        };
        extensions = {
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
  };
}
