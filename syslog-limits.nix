{ config, pkgs, lib, ... }:

let
  journaldLimitsConf = pkgs.writeText "99-log-limits.conf" ''
    [Journal]
    SystemMaxUse=1G
    SystemKeepFree=10G
    SystemMaxFileSize=64M
    RateLimitIntervalSec=30s
    RateLimitBurst=1000
  '';

  rsyslogDefaultConf = pkgs.writeText "50-default.conf" ''
    # Default rules for rsyslog with hard 200MB size cap on syslog and kern.log.
    $outchannel syslog_rotation,/var/log/syslog,209715200,/usr/lib/rsyslog/rsyslog-rotate
    $outchannel kernlog_rotation,/var/log/kern.log,209715200,/usr/lib/rsyslog/rsyslog-rotate

    auth,authpriv.*			/var/log/auth.log
    *.*;auth,authpriv.none		:omfile:$syslog_rotation
    kern.*				:omfile:$kernlog_rotation
    mail.*				-/var/log/mail.log
    mail.err			/var/log/mail.err
    *.emerg				:omusrmsg:*
  '';

  logrotateRsyslogConf = pkgs.writeText "rsyslog-logrotate" ''
    /var/log/syslog
    /var/log/mail.log
    /var/log/kern.log
    /var/log/auth.log
    /var/log/user.log
    /var/log/cron.log
    {
    	rotate 4
    	weekly
    	maxsize 100M
    	missingok
    	notifempty
    	compress
    	delaycompress
    	sharedscripts
    	postrotate
    		/usr/lib/rsyslog/rsyslog-rotate
    	endscript
    }
  '';

  logrotateTimerHourlyConf = pkgs.writeText "logrotate-hourly.conf" ''
    [Timer]
    OnCalendar=
    OnCalendar=hourly
    RandomizedDelaySec=5m
  '';

  applySyslogLimits = pkgs.writeShellScriptBin "apply-syslog-limits" ''
    set -euo pipefail

    needs_update=0
    for pair in \
      "${journaldLimitsConf}:/etc/systemd/journald.conf.d/99-log-limits.conf" \
      "${rsyslogDefaultConf}:/etc/rsyslog.d/50-default.conf" \
      "${logrotateRsyslogConf}:/etc/logrotate.d/rsyslog" \
      "${logrotateTimerHourlyConf}:/etc/systemd/system/logrotate.timer.d/hourly.conf"
    do
      src="''${pair%%:*}"
      dst="''${pair##*:}"
      if ! cmp -s "$src" "$dst" 2>/dev/null; then
        needs_update=1
        break
      fi
    done

    if [ -e /etc/rsyslog.d/00-rate-limit.conf ]; then
      needs_update=1
    fi

    if [ "$needs_update" -eq 0 ] && [ -f /var/log/syslog ]; then
      exit 0
    fi

    if [ "''${1:-}" = "--check" ]; then
      exit 1
    fi

    echo "Applying system log size & rate limits to /etc (requires sudo)..."
    /usr/bin/sudo /bin/sh -c '
      set -eu
      mkdir -p /etc/systemd/journald.conf.d /etc/rsyslog.d /etc/systemd/system/logrotate.timer.d
      rm -f /etc/rsyslog.d/00-rate-limit.conf
      install -m 0644 "${journaldLimitsConf}" /etc/systemd/journald.conf.d/99-log-limits.conf
      install -m 0644 "${rsyslogDefaultConf}" /etc/rsyslog.d/50-default.conf
      install -m 0644 "${logrotateRsyslogConf}" /etc/logrotate.d/rsyslog
      install -m 0644 "${logrotateTimerHourlyConf}" /etc/systemd/system/logrotate.timer.d/hourly.conf
      systemctl daemon-reload
      systemctl restart systemd-journald
      systemctl restart rsyslog
      systemctl restart logrotate.timer
      journalctl --rotate
      journalctl --vacuum-size=500M
    '
  '';
in
{
  home.packages = [
    applySyslogLimits
  ];

  # Mask failing/noisy Ubuntu Insights telemetry units in user scope
  xdg.configFile = {
    "systemd/user/ubuntu-insights-upload.timer".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
    "systemd/user/ubuntu-insights-collect.timer".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
    "systemd/user/ubuntu-insights-upload.service".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
    "systemd/user/ubuntu-insights-collect.service".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
  };

  # Automatically check and apply syslog limits during home-manager switch if sudo is cached
  home.activation.applySyslogLimits = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if /usr/bin/sudo -n true 2>/dev/null; then
      $DRY_RUN_CMD ${applySyslogLimits}/bin/apply-syslog-limits
    else
      ${applySyslogLimits}/bin/apply-syslog-limits --check || echo "Note: System log limits in /etc need updating. Run 'apply-syslog-limits' in a terminal to apply with sudo."
    fi
  '';
}
