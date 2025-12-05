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
        ];
      };
    "org/gnome/desktop/interface".show-battery-percentage = true;
    };
  };
}

