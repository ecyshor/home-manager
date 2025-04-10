{ config, pkgs, ... }:

{
  programs.nixvim = {
    plugins = {
      neogit.enable = true;
      gitsigns.enable = true;
      diffview.enable = true;
    };
    keymaps = [
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
