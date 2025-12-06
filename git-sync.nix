{config, pkgs, ...}: {
  systemd.user.services.git-pull-home-manager = {
    Unit = {
      Description = "Git pull for home-manager repository";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart =
        let
          script = pkgs.writeShellScript "git-pull-notify" ''
            set -eu
            export DISPLAY=:0
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
            cd "${config.home.homeDirectory}/.config/home-manager"
            OLD_HEAD=$(${pkgs.git}/bin/git rev-parse HEAD)
            ${pkgs.git}/bin/git pull
            NEW_HEAD=$(${pkgs.git}/bin/git rev-parse HEAD)
            if [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
              ${pkgs.libnotify}/bin/notify-send "Home Manager" "Configuration updated. Run home-manager switch."
            fi
          '';
        in
          "${script}";
    };
  };

  systemd.user.timers.git-pull-home-manager = {
    Unit = {
      Description = "Timer for git-pull-home-manager service";
    };
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "12h"; # 43200 seconds
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}