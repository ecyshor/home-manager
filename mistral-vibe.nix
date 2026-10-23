{ pkgs, ... }: {
  home.file.".vibe/config.toml".force = true;
  programs.mistral-vibe = {
    enable = true;
    package = pkgs.mistral-vibe.overridePythonAttrs (_: {
      doCheck = false;
    });
    # Custom settings can be added here, e.g.:
    # settings = {
    #   theme = "auto";
    # };
  };
}
