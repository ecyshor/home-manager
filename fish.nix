{ pkgs, lib, ... }:
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
        # legacy
        if test -e ~/.nix-profile/etc/profile.d/nix.fish
          source ~/.nix-profile/etc/profile.d/nix.fish
        end
        if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
          source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
          source /nix/var/nix/profiles/default/etc/profile.d/nix.fish
        end
        fzf_configure_bindings --directory=\\cf
        fzf_configure_bindings --git_log=\\cg
        fzf_configure_bindings --git_status=\\cs
        fzf_configure_bindings --history=\\cr
        fzf_configure_bindings --variables=\\cv
        fzf_configure_bindings --processes=\\cp
        set fzf_fd_opts --hidden
      ";
      shellAbbrs = {
        hms = "home-manager switch";
        ccs = "claude-sessions";
        nrs = "sudo nixos-rebuild switch";
        psl = "btm --expanded --default_widget_type=proc";
        pst = "btm --expanded --default_widget_type=proc --tree";
        rm = "trash";
        vic = "vi /etc/nixos/configuration.nix";
        vih = "cd .config/home-manager && vi .";
        vin = "vi ~/.config/nvim/init.lua";
        sys = "systemctl";
        syu = "systemctl --user";
        make = "make -j8";
      };
      shellAliases = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        lgs = "${pkgs.systemd}/bin/journalctl --user -o json -f -u git-pull-home-manager.service | ${pkgs.lnav}/bin/lnav";
      };
      functions = {
        # custom functions
        mkcd = ''
          mkdir -p $argv
          and cd $argv
        '';
        # fish history dedups commands, so log every execution for frequency stats
        __cmdlog_postexec = {
          onEvent = "fish_postexec";
          body = ''
            set -l st $status
            set -q fish_private_mode; and return
            string match -qr '^\s*$' -- "$argv[1]"; and return
            string match -q ' *' -- "$argv[1]"; and return
            set -l data (set -q XDG_DATA_HOME; and echo $XDG_DATA_HOME; or echo ~/.local/share)
            set -l cmd (string replace -a \t ' ' -- $argv[1] | string join '\n')
            printf '%s\t%s\t%s\t%s\n' (${pkgs.coreutils}/bin/date +%s) $st $PWD "$cmd" >>$data/fish/cmd_log.tsv
          '';
        };
        # cmdstats [-n N] [-w WORDS] [--since DAYS] [--score]
        cmdstats = ''
          argparse 'n=' 'w=' 'since=' score -- $argv; or return
          set -l data (set -q XDG_DATA_HOME; and echo $XDG_DATA_HOME; or echo ~/.local/share)
          set -l n (set -q _flag_n; and echo $_flag_n; or echo 30)
          set -l w (set -q _flag_w; and echo $_flag_w; or echo 0)
          set -l cutoff 0
          set -q _flag_since; and set cutoff (math (${pkgs.coreutils}/bin/date +%s) - $_flag_since \* 86400)
          set -l key 1
          set -q _flag_score; and set key 3
          ${pkgs.gawk}/bin/awk -F '\t' -v w=$w -v cutoff=$cutoff '
            $1 >= cutoff {
              c = $4
              if (w > 0) { k = split(c, a, / +/); c = a[1]; for (i = 2; i <= w && i <= k; i++) c = c " " a[i] }
              cnt[c]++
            }
            END { for (c in cnt) { l = length(c); printf "%d\t%d\t%d\t%s\n", cnt[c], l, cnt[c] * (l > 2 ? l - 2 : 0), c } }
          ' $data/fish/cmd_log.tsv \
            | ${pkgs.coreutils}/bin/sort -t \t -k$key,$key -nr | ${pkgs.coreutils}/bin/head -n $n \
            | ${pkgs.util-linux}/bin/column -t -s \t -N count,len,score,command
        '';
      };
    };
   }
