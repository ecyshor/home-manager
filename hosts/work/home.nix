{ config, pkgs, ... }:
{
  imports = [
    ./fish.nix
  ];
  home.packages = [
    (pkgs.writeScriptBin "sync-cluster" (builtins.readFile ./cni_sync_cluster_changes.fish))
  ];
}
