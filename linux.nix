# Linux-only parts shared by the XPS and work laptops: GNOME/i3 desktop,
# systemd/syslog tuning, power management, desktop entries and MIME handlers.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./gemeni-cli.nix
    ./dconf.nix
    ./systemd-notifier.nix
    ./syslog-limits.nix
    ./i3.nix
    ./agent-sleep-inhibitor.nix
  ];

  home.packages = [
    pkgs._1password-gui
    pkgs.xclip
    pkgs.pmutils
    pkgs.auto-cpufreq
    pkgs.desktop-file-utils
    # Override proton-pass to disable Electron sandbox (chrome-sandbox setuid issue on non-NixOS)
    # and suppress Chromium stderr log floods (--log-level=3)
    (pkgs.proton-pass.overrideAttrs (old: {
      preFixup = (old.preFixup or "") + ''
        wrapProgram $out/bin/proton-pass \
          --set ELECTRON_DISABLE_SANDBOX 1 \
          --add-flags "--log-level=3"
      '';
    }))
  ];

  xdg.configFile."auto-cpufreq/auto-cpufreq.conf".text = ''
     [charger]
     governor = performance
     energy_performance_preference = performance
     # Force the Bias to performance to match the EPP
     energy_perf_bias = performance
     turbo = auto

     [battery]
     governor = powersave
     energy_performance_preference = balance_power
     energy_perf_bias = power
     turbo = auto
  '';

  # Register proton-pass as handler for protonpass:// URLs
  # Needed because Snap Firefox can't see desktop entries in nix-profile
  xdg.dataFile."applications/proton-pass.desktop".text = ''
    [Desktop Entry]
    Name=Proton Pass
    Comment=Proton Pass desktop application
    GenericName=Password Manager
    Exec=${config.home.homeDirectory}/.nix-profile/bin/proton-pass %U
    Icon=proton-pass
    Type=Application
    StartupNotify=true
    Categories=Utility;
    MimeType=x-scheme-handler/protonpass;
  '';

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/protonpass" = "proton-pass.desktop";
      "x-scheme-handler/antigravity" = "antigravity.desktop";
    };
  };

  # Update desktop database after files are linked (for MIME associations)
  home.activation.updateDesktopDatabase = lib.hm.dag.entryAfter ["linkGeneration"] ''
    $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database ${config.home.homeDirectory}/.local/share/applications
  '';
}
