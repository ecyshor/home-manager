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
      After = [
        "graphical-session.target"
        "gnome-keyring-daemon.service"
        "dbus.service"
      ];
      Wants = [ "gnome-keyring-daemon.service" ];
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.proton-pass-cli}/bin/pass-cli ssh-agent start --vault-name Personal --socket-path %h/.ssh/proton-pass-agent.sock";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
