{ config, pkgs, lib, ... }:

let
  modifier = "Mod4"; # Super/Windows key
  # Patch alacritty with Nixpkgs Mesa/libglvnd RPATH and EGL vendor config so OpenGL
  # works on non-NixOS (Wayland & X11) without /run/opengl-driver or LD_LIBRARY_PATH.
  alacritty = pkgs.symlinkJoin {
    name = "alacritty-${pkgs.alacritty.version}";
    paths = [ pkgs.alacritty ];
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.patchelf
    ];
    postBuild = ''
      mkdir -p $out/lib/alacritty-glvnd
      cp -a ${pkgs.libglvnd}/lib/*.so* $out/lib/alacritty-glvnd/
      chmod -R u+w $out/lib/alacritty-glvnd
      for f in $out/lib/alacritty-glvnd/*.so*; do
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          old_rpath=$(patchelf --print-rpath "$f")
          patchelf --set-rpath "$out/lib/alacritty-glvnd:${pkgs.mesa}/lib:$old_rpath" "$f"
        fi
      done

      rm $out/bin/alacritty
      cp ${pkgs.alacritty}/bin/alacritty $out/bin/alacritty
      chmod u+w $out/bin/alacritty
      old_rpath=$(patchelf --print-rpath $out/bin/alacritty)
      patchelf --set-rpath "$out/lib/alacritty-glvnd:${pkgs.mesa}/lib:$old_rpath" $out/bin/alacritty

      wrapProgram $out/bin/alacritty \
        --set __EGL_VENDOR_LIBRARY_DIRS "${pkgs.mesa}/share/glvnd/egl_vendor.d"
    '';
  };
  terminal = "${alacritty}/bin/alacritty";
  menu = "${pkgs.rofi}/bin/rofi -show drun";
in
{
  home.packages = [
    alacritty          # terminal
    pkgs.rofi          # application launcher
    pkgs.i3status-rust # status bar
    pkgs.feh           # wallpaper
    pkgs.dunst         # notifications
    pkgs.playerctl     # media keys
    pkgs.brightnessctl # brightness keys
    pkgs.pavucontrol   # audio control
    pkgs.maim          # screenshots
    pkgs.xclip
  ];

  # Enable the X session so a display manager (or startx) can launch i3.
  xsession = {
    enable = true;
    windowManager.i3 = {
      enable = true;
      config = {
        inherit modifier terminal menu;

        fonts = {
          names = [ "FiraCode Nerd Font" ];
          size = 10.0;
        };

        keybindings = lib.mkOptionDefault {
          # Launchers
          "${modifier}+Return" = "exec ${terminal}";
          "${modifier}+d" = "exec ${menu}";
          "${modifier}+Shift+q" = "kill";

          # Focus (vim-style)
          "${modifier}+h" = "focus left";
          "${modifier}+j" = "focus down";
          "${modifier}+k" = "focus up";
          "${modifier}+l" = "focus right";

          # Move windows (vim-style)
          "${modifier}+Shift+h" = "move left";
          "${modifier}+Shift+j" = "move down";
          "${modifier}+Shift+k" = "move up";
          "${modifier}+Shift+l" = "move right";

          # Layout
          "${modifier}+f" = "fullscreen toggle";
          "${modifier}+e" = "layout toggle split";
          "${modifier}+w" = "layout tabbed";
          "${modifier}+s" = "layout stacking";
          "${modifier}+Shift+space" = "floating toggle";

          # Session
          "${modifier}+Shift+c" = "reload";
          "${modifier}+Shift+r" = "restart";
          "${modifier}+Shift+e" =
            "exec i3-nagbar -t warning -m 'Exit i3?' -b 'Yes' 'i3-msg exit'";

          # Media & brightness keys
          "XF86AudioRaiseVolume" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%";
          "XF86AudioLowerVolume" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%";
          "XF86AudioMute" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle";
          "XF86AudioPlay" = "exec --no-startup-id ${pkgs.playerctl}/bin/playerctl play-pause";
          "XF86AudioNext" = "exec --no-startup-id ${pkgs.playerctl}/bin/playerctl next";
          "XF86AudioPrev" = "exec --no-startup-id ${pkgs.playerctl}/bin/playerctl previous";
          "XF86MonBrightnessUp" = "exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set +5%";
          "XF86MonBrightnessDown" = "exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";

          # Screenshot (selection to clipboard)
          "Print" = "exec --no-startup-id ${pkgs.maim}/bin/maim -s | ${pkgs.xclip}/bin/xclip -selection clipboard -t image/png";
        };

        bars = [{
          statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ${config.xdg.configHome}/i3status-rust/config-default.toml";
          position = "top";
          fonts = {
            names = [ "FiraCode Nerd Font" ];
            size = 10.0;
          };
        }];

        startup = [
          { command = "${pkgs.dunst}/bin/dunst"; notification = false; }
        ];
      };
    };
  };

  # Status bar configuration
  programs.i3status-rust = {
    enable = true;
    bars.default = {
      blocks = [
        { block = "cpu"; interval = 1; }
        { block = "memory"; format = " $icon $mem_used_percents "; }
        { block = "disk_space"; path = "/"; info_type = "available"; interval = 60; warning = 20.0; alert = 10.0; }
        { block = "sound"; }
        { block = "battery"; }
        { block = "time"; interval = 5; format = " $timestamp.datetime(f:'%a %d/%m %R') "; }
      ];
      theme = "gruvbox-dark";
      icons = "awesome6";
    };
  };
}
