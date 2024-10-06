{ config, pkgs, ... }:
{
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };
  home.packages = [
    pkgs.ansible
    pkgs.sshpass
    pkgs.mullvad-vpn
  ];
}
