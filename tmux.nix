{ pkgs, ... }:
let
  # fix for https://github.com/tmux-plugins/tmux-resurrect/issues/287
  fix-tmux-resurrect-script = pkgs.writeShellScriptBin "fix-tmux-resurrect" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    RESURRECT_DIR="$HOME/.tmux/resurrect"
    LAST_SYMLINK="$RESURRECT_DIR/last"

    # 1. Exit if the 'last' symlink doesn't exist.
    if [[ ! -L "$LAST_SYMLINK" ]]; then
      # You can uncomment the next line for debugging if you want.
      # echo "Tmux-resurrect: 'last' symlink not found. Exiting."
      exit 0
    fi

    # 2. Get the full path of the file the symlink points to.
    TARGET_FILE=$(readlink -f "$LAST_SYMLINK")

    # 3. If the target file has content (is not empty), we're done.
    if [[ -s "$TARGET_FILE" ]]; then
      exit 0
    fi

    # --- At this point, the 'last' file is empty. Let's fix it. ---
    echo "Tmux-resurrect: 'last' session file is empty. Searching for a replacement."

    LATEST_NON_EMPTY_FILE=""
    # 4. Loop through all resurrect files to find the newest one that isn't empty.
    for file in "$RESURRECT_DIR"/tmux_resurrect_*.txt; do
      # Ensure it's a file and it's not empty
      if [[ -f "$file" && -s "$file" ]]; then
        # If this is the first valid file we've found, or it's newer than the last one...
        if [[ -z "$LATEST_NON_EMPTY_FILE" || "$file" -nt "$LATEST_NON_EMPTY_FILE" ]]; then
          LATEST_NON_EMPTY_FILE="$file"
        fi
      fi
    done

    # 5. If we found a suitable replacement, update the symlink.
    if [[ -n "$LATEST_NON_EMPTY_FILE" ]]; then
      # -s: symbolic, -f: force overwrite
      ln -sf "$LATEST_NON_EMPTY_FILE" "$LAST_SYMLINK"
      echo "Tmux-resurrect: Symlink 'last' now points to $LATEST_NON_EMPTY_FILE"
    else
      echo "Tmux-resurrect: No non-empty session files found to replace 'last'."
    fi
  '';
in
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
    focusEvents = true;
    mouse = true;
    # Force tmux to use /tmp for sockets (WSL2 compat)
    secureSocket = false;
    shell = "${pkgs.fish}/bin/fish";
    terminal = "tmux-256color";

    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
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
          ## Strip Nix wrapper flags (--cmd set packpath/rtp) and /nix/store/.../bin/ paths
          ## so restored Neovim runs via the PATH wrapper instead of neovim-unwrapped with unquoted --cmd args
          set -g @resurrect-hook-post-save-layout "${pkgs.gnused}/bin/sed -i -E 's| --cmd set [^ ]*||g; s|/nix/store/[^/[:space:]]*/bin/||g'"
        '';
      }
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          # Disable startup on boot because tmux starts too early and lots of shit is broken (colors, copy, startin graphical apps)
          # set -g @continuum-boot 'on'
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60' # minutes
        '';
      }
    ];

    extraConfig = ''
      # increase timeout to select pane
      set -g display-panes-time 4000

      # Truecolor, extended keys (Shift+Enter in Claude Code / Mistral Vibe),
      # DCS passthrough (\ePtmux;...\e\ used by both Claude & Vibe), and OSC 52 clipboard
      set -as terminal-features ",*:RGB,*:extkeys"
      set -s extended-keys on
      set -g allow-passthrough on
      set -g set-clipboard on

      # easy-to-remember split pane commands
      bind "|" split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"
      # Renumber windows so that indices are always a complete sequence
      set-option -g renumber-windows on

      # Live Claude Code sessions indicator in the status bar + popup switcher (Prefix + C)
      set -g status-interval 3
      set -g status-right-length 80
      set -g status-right "#(claude-sessions --status-bar 2>/dev/null) | %H:%M %d-%b-%y"
      bind C display-popup -E -w 85% -h 80% "claude-sessions"

      # Spawn Claude Code in a right-hand split (Prefix + a) or isolated git worktree (Prefix + A)
      bind a split-window -h -l 40% -c "#{pane_current_path}" "claude"
      bind A command-prompt -p "Claude worktree:" "split-window -h -l 40% -c '#{pane_current_path}' 'claude -w \"%%\"'"
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

  
  systemd.user.services.fix-tmux-resurrect = {
    Unit = {
      Description = "Fix empty tmux-resurrect 'last' file on startup";
      # This service doesn't need network or anything complex
      After = [ "graphical-session-pre.target" ];
    };

    Service = {
      Type = "oneshot"; # It runs once and then exits
      # The script to execute
      ExecStart = "${fix-tmux-resurrect-script}/bin/fix-tmux-resurrect";
    };

    Install = {
      # This ensures the service is started when you log in
      WantedBy = [ "default.target" ];
    };
  };
}
