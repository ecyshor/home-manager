{ config, pkgs, git, lib, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "nicu";
  home.homeDirectory = "/home/nicu";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  imports = [
    ./git-sync.nix
    ./fish.nix 
    ./tmux.nix 
    ./fzf.nix 
    ./starship.nix 
    ./direnv.nix 
    ./nvim 
    ./gemeni-cli.nix
    ./dconf.nix
    ./systemd-notifier.nix
    ./syslog-limits.nix
    ./i3.nix
  ];

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    pkgs.nerd-fonts.fira-code
    pkgs.trash-cli
    pkgs.fd
    pkgs.ncdu
    pkgs.lnav
    pkgs.bottom
    pkgs.jq
    pkgs.go
    pkgs._1password-cli
    pkgs._1password-gui
    pkgs.gnumake
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
    pkgs.proton-pass-cli

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;
    ".ssh/config".text = ''
      Host *
        IdentityAgent ${config.home.homeDirectory}/.ssh/proton-pass-agent.sock
    '';


    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  xdg.configFile."auto-cpufreq/auto-cpufreq.conf".text = ''
     [charger]
     governor = performance
     energy_performance_preference = performance
     # Force the Bias to performance to match the EPP
     energy_perf_bias = performance
     turbo = always

     [battery]
     governor = powersave
     energy_performance_preference = balance_power
     energy_perf_bias = power
     turbo = auto
  '';

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/nicu/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "vim";
    SSH_AUTH_SOCK = "${config.home.homeDirectory}/.ssh/proton-pass-agent.sock";
  };

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

  nixpkgs.config = {
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "1password"
      "1password-cli"
      "1password-gui"
      "antigravity-cli"
      "claude-code"
      "mistral-vibe"
      "textual-speedups" # Dependency of mistral-vibe; marked unfree in nixpkgs due to lack of upstream license
      "proton-pass"
      "proton-pass-cli"
    ];
    # Alternatively, you can allow all unfree packages with:
    # allowUnfree = true;
  };

  # Let Home Manager install and manage itself.
  programs = { 
    home-manager.enable = true; 
    ripgrep.enable = true; 
    gh.enable = true;
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  # Add global git prepare-commit-msg hook for sign-off
  programs.git = {
    enable = true;
    settings = {
      user.name = git.name;
      user.email = git.email;
    };
    signing.format = null;
  };

  home.file.".config/git/hooks/prepare-commit-msg" = {
    text = ''
      #!/bin/sh
      # Only add Signed-off-by if not already present and not a merge or squash
      case "$2" in
        merge|squash) exit 0 ;;
      esac

      SIGNOFF="Signed-off-by: ${git.name} <${git.email}>"

      if ! grep -qi "^Signed-off-by: " "$1"; then
        echo "" >> "$1"
        echo "$SIGNOFF" >> "$1"
      fi
    '';
    executable = true;
  };

  # Update desktop database after files are linked (for MIME associations)
  home.activation.updateDesktopDatabase = lib.hm.dag.entryAfter ["linkGeneration"] ''
    $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database ${config.home.homeDirectory}/.local/share/applications
  '';
}
