{ config, pkgs, ... }:

{
  programs.nixvim = {
    plugins = {
      neo-tree.enable = true;
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
