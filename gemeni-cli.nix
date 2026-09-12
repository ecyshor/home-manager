{pkgs, ...}: {
  home.file.".gemini/antigravity-cli/settings.json".force = true;
  programs.antigravity-cli = {
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
