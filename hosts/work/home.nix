{ config, pkgs, ... }:
{
  imports = [
    ./fish.nix
  ];
  home.packages = [
    pkgs.networkmanager-l2tp
  ];
}
