# macOS counterpart of agent-sleep-inhibitor.nix: keep the Mac from idle-sleeping
# while a Claude Code or Mistral Vibe agent is working, unless on battery below 30%.
# Uses `caffeinate -i` (idle sleep only), so closing the lid still sleeps the Mac.
# No inotify on macOS, so session state is polled; the check is pure bash.
{ pkgs, config, ... }:
let
  agent-sleep-inhibitor = pkgs.writeShellApplication {
    name = "agent-sleep-inhibitor";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Same state dirs the Claude hook and the Vibe patch write to
      RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/tmp}"
      CLAUDE_DIR="$RUNTIME_DIR/claude-sessions"
      VIBE_DIR="$RUNTIME_DIR/vibe-sessions"
      MIN_BATTERY_PCT=30
      STALE_WORKING_SECS=1800
      POLL_ACTIVE_SECS=30
      POLL_IDLE_SECS=15

      mkdir -p "$CLAUDE_DIR" "$VIBE_DIR"

      INHIBIT_PID=""

      stop_inhibitor() {
        if [[ -n "$INHIBIT_PID" ]]; then
          if kill -0 "$INHIBIT_PID" 2>/dev/null; then
            kill "$INHIBIT_PID" 2>/dev/null || true
            wait "$INHIBIT_PID" 2>/dev/null || true
          fi
          INHIBIT_PID=""
        fi
      }

      trap stop_inhibitor EXIT INT TERM

      # Sets AC=1/0 and REPLY=<battery %> from `pmset -g batt`
      # (desktops without a battery count as AC at 100%)
      read_power() {
        local out
        out="$(/usr/bin/pmset -g batt 2>/dev/null || true)"
        AC=0
        [[ "$out" == *"'AC Power'"* ]] && AC=1
        REPLY=100
        if [[ "$out" =~ ([0-9]+)% ]]; then
          REPLY="''${BASH_REMATCH[1]}"
        fi
      }

      has_active_agent() {
        shopt -s nullglob
        local now f content pid state updated
        printf -v now '%(%s)T' -1

        for f in "$CLAUDE_DIR"/*.json "$VIBE_DIR"/*.json; do
          [[ "''${f##*/}" == "claude-quota.json" || "''${f##*/}" == "vibe-usage.cache" ]] && continue
          [[ -r "$f" ]] || continue
          content="$(<"$f")" || continue

          pid=""
          state=""
          updated=0
          if [[ "$content" =~ \"pid\":[[:space:]]*([0-9]+) ]]; then
            pid="''${BASH_REMATCH[1]}"
          fi
          if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$f"
            continue
          fi

          if [[ "$content" =~ \"state\":[[:space:]]*\"([^\"]+)\" ]]; then
            state="''${BASH_REMATCH[1]}"
          fi
          if [[ "$content" =~ \"updated_at\":[[:space:]]*([0-9]+) ]]; then
            updated="''${BASH_REMATCH[1]}"
          fi

          if [[ "$state" == "working" ]]; then
            # Vibe only writes on turn transitions (PID liveness is enough);
            # Claude can get stuck at "working" after an interrupt, so keep the staleness guard.
            if [[ "$f" == "$VIBE_DIR"/* ]] || (( now - updated < STALE_WORKING_SECS )); then
              return 0
            fi
          fi
        done

        return 1
      }

      start_inhibitor() {
        if [[ -n "$INHIBIT_PID" ]] && kill -0 "$INHIBIT_PID" 2>/dev/null; then
          return
        fi
        /usr/bin/caffeinate -i &
        INHIBIT_PID="$!"
      }

      while true; do
        if has_active_agent; then
          read_power
          if (( AC == 1 || REPLY >= MIN_BATTERY_PCT )); then
            start_inhibitor
          else
            stop_inhibitor
          fi
          sleep "$POLL_ACTIVE_SECS"
        else
          stop_inhibitor
          sleep "$POLL_IDLE_SECS"
        fi
      done
    '';
  };
in
{
  home.packages = [ agent-sleep-inhibitor ];

  launchd.agents.agent-sleep-inhibitor = {
    enable = true;
    # Start via a launcher named after the agent, so System Settings > Login Items
    # shows "agent-sleep-inhibitor" instead of "sh" (/nix is mounted at boot, before login).
    waitForNixStore = false;
    config = {
      ProgramArguments = [ "${agent-sleep-inhibitor}/bin/agent-sleep-inhibitor" ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-sleep-inhibitor.log";
    };
  };
}
