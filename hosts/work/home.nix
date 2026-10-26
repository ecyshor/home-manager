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

  # Proton Pass CLI SSH agent — restricted to the "Digital Asset" vault
  systemd.user.services.proton-pass-ssh-agent = {
    Unit = {
      Description = "Proton Pass SSH Agent (Digital Asset vault)";
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.proton-pass-cli}/bin/pass-cli ssh-agent start --vault-name 'Digital Asset' --socket-path %h/.ssh/proton-pass-agent.sock";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
