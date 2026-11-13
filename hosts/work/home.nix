{ config, lib, pkgs, ... }:
let
  protonPassSshAgentStart = pkgs.writeShellScript "proton-pass-ssh-agent-start" ''
    set -euo pipefail

    if ! "${pkgs.proton-pass-cli}/bin/pass-cli" info >/dev/null; then
      "${pkgs.proton-pass-cli}/bin/pass-cli" login | while IFS= read -r line; do
        printf '%s\n' "$line"
        if [[ "$line" =~ (https://[^[:space:]]+) ]]; then
          /usr/bin/xdg-open "''${BASH_REMATCH[1]}" >/dev/null 2>&1 &
        fi
      done
    fi

    exec "${pkgs.proton-pass-cli}/bin/pass-cli" ssh-agent start --vault-name 'Digital Asset' --socket-path "$HOME/.ssh/proton-pass-agent.sock"
  '';
in
{
  imports = [
    ./fish.nix
    ../../thermald-no-adaptive.nix
  ];
  home.packages = [
  ];
  home.file = {
    ".ssh/config".text = lib.mkBefore ''
      Include ${config.home.homeDirectory}/.config/sandboxes/sandboxes/ssh/config
    '';
    ".config/1Password/ssh/agent.toml".text = ''
      [[ssh-keys]]
      vault = "Digital Asset"
    '';
  };

  # Proton Pass CLI SSH agent — restricted to the "Digital Asset" vault
  systemd.user.services.proton-pass-ssh-agent = {
    Unit = {
      Description = "Proton Pass SSH Agent (Digital Asset vault)";
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
      ExecStart = "${protonPassSshAgentStart}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
