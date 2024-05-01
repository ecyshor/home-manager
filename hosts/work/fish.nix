{ pkgs,  ... }:
{
  programs.fish = {
      shellAbbrs = {
        cc = "cd ~/workspace/canton-network-node/cluster/deployment/";
      };
    };
   }
