{pkgs, ...}: {
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;

    defaultCommand = "${pkgs.fd}/bin/fd --hidden --type f";
    fileWidgetCommand = "${pkgs.fd}/bin/fd --hidden --type f";
    changeDirWidgetCommand = "${pkgs.fd}/bin/fd --hidden --type d";
    
  };

  home.file = { ".fdignore" = { text = ''.cache''; executable = false; };};

}
