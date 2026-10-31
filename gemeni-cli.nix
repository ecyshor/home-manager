{ pkgs, git, ... }: {
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
    # Global rules (~/.gemini/GEMINI.md)
    context.GEMINI = import ./agent-commit-policy.nix git;
  };
  home.file.".gemini/GEMINI.md".force = true;
}
