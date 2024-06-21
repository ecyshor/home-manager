{ config, pkgs, ... }:
{
  home.packages = [
    pkgs.ansible
  ];
}
