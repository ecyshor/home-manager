{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    historyLimit = 100000;
    keyMode = "vi";
    # aggressiveResize = true; -- Disabled to be iTerm-friendly
    baseIndex = 0;
    newSession = true;
    # Stop tmux+escape craziness.
    escapeTime = 0;
    # Force tmux to use /tmp for sockets (WSL2 compat)
    secureSocket = false;
    shell = "${pkgs.fish}/bin/fish";

    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.tmux-autoreload
      {
        plugin = tmuxPlugins.yank;
        extraConfig = ''
          set -g @override_copy_command 'xclip -in -selection clipboard'
        '';
      }
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-processes ':all:'
          ## Restore Vim sessions
          set -g @resurrect-strategy-vim 'session'
          ## Restore Neovim sessions
          set -g @resurrect-strategy-nvim 'session'
          ## Restore Panes
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-boot 'on'
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60' # minutes
        '';
      }
    ];

    extraConfig = ''
      # increase timeout to select pane
      set -g display-panes-time 4000
      # https://old.reddit.com/r/tmux/comments/mesrci/tmux_2_doesnt_seem_to_use_256_colors/
      set -g default-terminal "tmux-256color"
      #set -ga terminal-overrides ",*256col*:Tc"
      #set -ga terminal-overrides "*:Ss=\E[%p1%d q:Se=\E[ q"
      #set-environment -g COLORTERM "truecolor"

      # Mouse works as expected
      set-option -g mouse on
      # easy-to-remember split pane commands
      bind "|" split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"
      # Renumber windows so that indices are always a complete sequence
      set-option -g renumber-windows on
    '';
  };

  programs.tmate = {
    enable = false;
    # FIXME: This causes tmate to hang.
    # extraConfig = config.xdg.configFile."tmux/tmux.conf".text;
  };

  home.packages = [
    # Open tmux for current project.
    (pkgs.writeShellApplication {
      name = "pux";
      runtimeInputs = [ 
        pkgs.tmux
        pkgs.zoxide
      ];
      text = ''
        PRJ="''$(zoxide query -i)"
        echo "Launching tmux for ''$PRJ"
        set -x
        cd "''$PRJ" && \
          exec tmux -S "''$PRJ".tmux attach
      '';
    })
  ];
}
