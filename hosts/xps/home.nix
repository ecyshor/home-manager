{ config, pkgs, ... }:
{
  imports = [
    ../../mistral-vibe.nix
  ];

  home.packages = [
    pkgs.ansible
    pkgs.sshpass
  ];

  # Proton Pass CLI SSH agent — restricted to the "Personal" vault
  systemd.user.services.proton-pass-ssh-agent = {
    Unit = {
      Description = "Proton Pass SSH Agent (Personal vault)";
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.proton-pass-cli}/bin/pass-cli ssh-agent start --vault-name Personal --socket-path %h/.ssh/proton-pass-agent.sock";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
