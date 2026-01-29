{ pkgs, ... }:

{
  systemd.user.services.systemd-failure-notifier = {
    Unit = {
      Description = "Periodically checks for failed systemd user units and sends a notification.";
    };
    Service = {
      Type = "oneshot";
      ExecStart =
        let
          script = pkgs.writeShellScript "systemd-failure-notifier-script" ''
            set -eu
            export DISPLAY=:0
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
            
            failed_units=$(${pkgs.systemd}/bin/systemctl --user list-units --state=failed --no-legend --plain | awk '{print $1}')
            
            if [ -n "$failed_units" ]; then
              ${pkgs.libnotify}/bin/notify-send -u critical "Systemd Failures" "The following user services have failed:\n$failed_units"
            fi
          '';
        in
          "${script}";
    };
  };

  systemd.user.timers.systemd-failure-notifier = {
    Unit = {
      Description = "Timer for the systemd failure notifier service.";
    };
    Timer = {
      # Run 5 minutes after boot, and then every 15 minutes
      OnBootSec = "5m";
      OnUnitActiveSec = "2h";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
