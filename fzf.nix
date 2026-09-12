{pkgs, ...}: {
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;

    defaultCommand = "${pkgs.fd}/bin/fd --hidden --type f";
    fileWidget.command = "${pkgs.fd}/bin/fd --hidden --type f";
    changeDirWidget.command = "${pkgs.fd}/bin/fd --hidden --type d";
  };

  home.file = { ".fdignore" = { text = ''.cache''; executable = false; };};

}
