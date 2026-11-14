# Personal MacBook (Apple Silicon). Shared shell/editor setup comes from ../../home.nix;
# this adds the personal AI tooling and the macOS (launchd) versions of the XPS services.
{ config, pkgs, ... }:
let
  # Same as the XPS agent, but opens the login URL with macOS `open`.
  protonPassSshAgentStart = pkgs.writeShellScript "proton-pass-ssh-agent-start" ''
    set -euo pipefail

    if ! "${pkgs.proton-pass-cli}/bin/pass-cli" info >/dev/null; then
      "${pkgs.proton-pass-cli}/bin/pass-cli" login | while IFS= read -r line; do
        printf '%s\n' "$line"
        if [[ "$line" =~ (https://[^[:space:]]+) ]]; then
          /usr/bin/open "''${BASH_REMATCH[1]}" >/dev/null 2>&1 &
        fi
      done
    fi

    exec "${pkgs.proton-pass-cli}/bin/pass-cli" ssh-agent start --vault-name Personal --socket-path "$HOME/.ssh/proton-pass-agent.sock"
  '';
in
{
  imports = [
    ../../claude-code.nix
    ../../mistral-vibe.nix
    ../../agent-sleep-inhibitor-darwin.nix
    ../../zsh.nix
  ];

  home.packages = [
    pkgs.ansible
    pkgs.sshpass
  ];

  # GUI apps launched from Finder/Spotlight don't read the shell's SSH_AUTH_SOCK;
  # point the login session at the Proton Pass agent too.
  launchd.agents.ssh-auth-sock = {
    enable = true;
    # Start via a launcher named after the agent, so System Settings > Login Items
    # shows "ssh-auth-sock" instead of "sh" (/nix is mounted at boot, before login).
    waitForNixStore = false;
    config = {
      ProgramArguments = [
        "/bin/launchctl" "setenv" "SSH_AUTH_SOCK"
        "${config.home.homeDirectory}/.ssh/proton-pass-agent.sock"
      ];
      RunAtLoad = true;
    };
  };

  # Proton Pass CLI SSH agent — restricted to the "Personal" vault
  launchd.agents.proton-pass-ssh-agent = {
    enable = true;
    # Start via a launcher named after the agent, so System Settings > Login Items
    # shows "proton-pass-ssh-agent" instead of "sh" (/nix is mounted at boot, before login).
    waitForNixStore = false;
    config = {
      ProgramArguments = [ "${protonPassSshAgentStart}" ];
      RunAtLoad = true;
      # Restart if it exits with an error (e.g. not logged in yet), but not in a tight loop
      KeepAlive = { SuccessfulExit = false; };
      ThrottleInterval = 30;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/proton-pass-ssh-agent.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/proton-pass-ssh-agent.log";
    };
  };
}
