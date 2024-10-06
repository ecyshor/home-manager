{ config, pkgs, ... }:
{
  home.services = {
    mullvad-vpn.enable = true;
    mullvad-vpn.package = pkgs.mullvad-vpn;
  };
  home.packages = [
    pkgs.ansible
    pkgs.sshpass
    pkgs.mullvad-vpn
  ];
}
