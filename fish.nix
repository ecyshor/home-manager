{ pkgs,  ... }:
{
  programs.fish = {
      enable = true;
      interactiveShellInit = "
        set fish_greeting
      ";
      plugins = [
        {
          name = "fzf.fish";
          src = pkgs.fishPlugins.fzf-fish.src;
        }
      ];
      shellInit = "
        fish_vi_key_bindings
        fish_add_path ~/.local/share/bin/
        fzf_configure_bindings --directory=\\cf
        fzf_configure_bindings --git_log=\\cg
        fzf_configure_bindings --git_status=\\cs
        fzf_configure_bindings --history=\\cr
        fzf_configure_bindings --variables=\\cv
        fzf_configure_bindings --processes=\\cp
        source ~/.nix-profile/etc/profile.d/nix.fish
        set fzf_fd_opts --hidden
      ";
      shellAbbrs = {
        hms = "home-manager switch";
        nrs = "sudo nixos-rebuild switch";
        psl = "btm --expanded --default_widget_type=proc";
        pst = "btm --expanded --default_widget_type=proc --tree";
        rm = "trash";
        vic = "vi /etc/nixos/configuration.nix";
        vih = "vi ~/.config/home-manager";
        vin = "vi ~/.config/nvim/init.lua";
        sys = "systemctl";
        syu = "systemctl --user";
        make = "make -j8";
      };
      functions = {
        # custom functions
        mkcd = ''
          mkdir -p $argv
          and cd $argv
        '';
      };
    };
   }
