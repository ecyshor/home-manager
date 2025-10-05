
{pkgs, ...}: {
  programs.gemeni-cli = {
    enable = true;
    settings = {
      vimMode= true;
      preferredEditor = "vim";
    };
  };
}
