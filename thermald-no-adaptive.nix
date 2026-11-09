{ config, pkgs, lib, ... }:

# thermald --adaptive follows the BIOS DPTF tables and on the Dell Pro Max (Core Ultra 9 285HX)
# drives the MMIO RAPL PL1 down to 15W while the CPU is cool, pinning all cores at ~400MHz.
# Run thermald without --adaptive and reset the MMIO PL1 to the MSR PL1 on start.
let
  dropInPath = "/etc/systemd/system/thermald.service.d/no-adaptive.conf";

  dropIn = pkgs.writeText "thermald-no-adaptive.conf" ''
    [Service]
    ExecStartPre=-/bin/sh -c 'cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw'
    ExecStart=
    ExecStart=/usr/sbin/thermald --systemd --dbus-enable
  '';

  applyThermaldNoAdaptive = pkgs.writeShellScriptBin "apply-thermald-no-adaptive" ''
    set -euo pipefail

    if cmp -s "${dropIn}" "${dropInPath}" 2>/dev/null; then
      exit 0
    fi

    if [ "''${1:-}" = "--check" ]; then
      exit 1
    fi

    echo "Disabling thermald adaptive mode via ${dropInPath} (requires sudo)..."
    /usr/bin/sudo /bin/sh -c '
      set -eu
      mkdir -p "$(dirname "${dropInPath}")"
      install -m 0644 "${dropIn}" "${dropInPath}"
      systemctl daemon-reload
      systemctl restart thermald
    '
  '';
in
{
  home.packages = [
    applyThermaldNoAdaptive
  ];

  # Automatically apply during home-manager switch if sudo is cached
  home.activation.applyThermaldNoAdaptive = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if /usr/bin/sudo -n true 2>/dev/null; then
      $DRY_RUN_CMD ${applyThermaldNoAdaptive}/bin/apply-thermald-no-adaptive
    else
      ${applyThermaldNoAdaptive}/bin/apply-thermald-no-adaptive --check || echo "Note: thermald adaptive override in /etc needs updating. Run 'apply-thermald-no-adaptive' in a terminal to apply with sudo."
    fi
  '';
}
