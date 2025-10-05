
{pkgs, ...}: {
  programs.gemini-cli = {
    enable = true;
    settings = {
      vimMode= true;
      preferredEditor = "vim";
    };
  };
}
