{ config, pkgs, ... }:
{
  imports = [
    ./fish.nix
  ];
  home.packages = [
  ];
  home.file = {
    ".config/1Password/ssh/agent.toml".text = ''
      [[ssh-keys]]
      vault = "Digital Asset"
    '';
  };
}
