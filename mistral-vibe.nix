{ ... }: {
  home.file.".vibe/config.toml".force = true;
  programs.mistral-vibe = {
    enable = true;
    # Custom settings can be added here, e.g.:
    # settings = {
    #   theme = "auto";
    # };
  };
}
