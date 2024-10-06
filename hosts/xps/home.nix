{ config, pkgs, ... }:
{
  home.packages = [
    pkgs.ansible
    pkgs.sshpass
    pkgs.mullvad-vpn
  ];
}
