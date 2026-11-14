# Minimal zsh setup for the shells that still start zsh even with fish as the login
# shell (the Claude Code app, editors, scripts, `ssh` fallbacks). It loads the Home
# Manager session variables (EDITOR, SSH_AUTH_SOCK, ...) and the same direnv, zoxide,
# starship and fzf hooks as fish; their zsh integrations turn on with programs.zsh.
{ config, ... }:
{
  programs.zsh = {
    enable = true;
    # Keep zsh files out of $HOME
    dotDir = "${config.xdg.configHome}/zsh";
    # The Nix installer only hooks /etc/zshrc (interactive shells); load Nix's PATH
    # for every zsh, as fish.nix does, so scripts and tool shells find nix-profile/bin.
    # Nix's "already sourced" flag is exported, so a child can inherit it from a
    # parent whose PATH it doesn't share; decide by whether `nix` is on PATH instead.
    envExtra = ''
      if ! command -v nix >/dev/null 2>&1 && [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        unset __ETC_PROFILE_NIX_SOURCED
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi
    '';
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    defaultKeymap = "viins"; # vi mode, like fish_vi_key_bindings
    history = {
      size = 100000;
      save = 100000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreSpace = true;
      ignoreAllDups = true;
      share = true;
    };
    # The same helpers as the fish abbreviations that make sense in zsh
    shellAliases = {
      hms = "home-manager switch";
      vih = "cd ~/.config/home-manager && vi .";
      psl = "btm --expanded --default_widget_type=proc";
      pst = "btm --expanded --default_widget_type=proc --tree";
    };
  };
}
