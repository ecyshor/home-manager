{pkgs, ...}: {
  home.file.".gemini/settings.json".force = true;
  programs.gemini-cli = {
    enable = true;
    settings = {
      vimMode= true;
      preferredEditor = "vim";
      previewFeatures= true;
    };
  };
}
