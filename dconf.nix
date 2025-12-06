{ pkgs, ... }:
{
  home.packages = [
    pkgs.gnome-extension-manager
    pkgs.gnomeExtensions.clipboard-indicator
    # vitals
    pkgs.lm_sensors
    pkgs.gnomeExtensions.vitals
  ];
  dconf = {
   enable = true;
   settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/shell" = {
      enabled-extensions = [
        "clipboard-indicator@tudmotu.com"
        "Vitals@CoreCoding.com"
        ];
      disabled-extensions = [
        "ubuntu-dock@ubuntu.com"
      ];
      };
    "org/gnome/desktop/interface".show-battery-percentage = true;
    "org/gnome/shell/extensions/vitals" = {
      hot-sensors = [ "_storage_free_" "_memory_usage_" "_system_load_1m_" "__network-rx_max__" ];
      position-in-panel = 0;
    };
    };
  };
}

