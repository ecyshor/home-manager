{pkgs, ...}: {
  home.file.".gemini/settings.json".force = true;
  programs.gemini-cli = {
    enable = true;
    settings = {
      general = {
        vimMode= true;
        preferredEditor = "vim";
        previewFeatures= true;
      };
      security.auth.selectedType = "oauth-personal";
    };
  };
}
