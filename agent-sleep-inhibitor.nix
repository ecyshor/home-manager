{ pkgs, ... }:
let
  agent-sleep-inhibitor = pkgs.writeShellApplication {
    name = "agent-sleep-inhibitor";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnome-session
      pkgs.inotify-tools
      pkgs.systemd
    ];
    text = ''
      RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/''${UID}}"
      CLAUDE_DIR="$RUNTIME_DIR/claude-sessions"
      VIBE_DIR="$RUNTIME_DIR/vibe-sessions"
      MIN_BATTERY_PCT=30
      STALE_WORKING_SECS=1800

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

      get_battery_pct() {
        shopt -s nullglob
        local bat_caps=(/sys/class/power_supply/BAT*/capacity)
        if (( ''${#bat_caps[@]} == 0 )); then
          REPLY=100
          return
        fi
        REPLY=100
        if [[ -r "''${bat_caps[0]}" ]]; then
          read -r REPLY < "''${bat_caps[0]}" || REPLY=100
        fi
      }

      # On AC power the battery threshold is irrelevant: always allow inhibiting.
      on_ac_power() {
        shopt -s nullglob
        local d t o
        for d in /sys/class/power_supply/*; do
          [[ -r "$d/type" && -r "$d/online" ]] || continue
          read -r t < "$d/type" || continue
          [[ "$t" == "Mains" ]] || continue
          read -r o < "$d/online" || continue
          [[ "$o" == "1" ]] && return 0
        done
        return 1
      }

      # Pure bash check (zero subprocess forks) over session JSON files
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
            # Vibe writes its state in-process and only on turn transitions, so a
            # single long turn (e.g. a 60-minute delegated task) never refreshes
            # updated_at; the PID liveness check above is sufficient for it.
            # Claude state comes from hooks and can get stuck at "working" when a
            # turn is interrupted (no Stop hook), so keep the staleness guard.
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

        local reason="Claude/Mistral agent actively working (on AC or battery >= ''${MIN_BATTERY_PCT}%)"
        if [[ -S "$RUNTIME_DIR/bus" ]]; then
          export DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus"
          systemd-inhibit \
            --what=idle:sleep \
            --who="AI Agent" \
            --why="$reason" \
            --mode=block \
            gnome-session-inhibit \
              --app-id "ai-agent" \
              --reason "$reason" \
              --inhibit suspend \
              --inhibit idle \
              --inhibit-only >/dev/null 2>&1 &
          INHIBIT_PID="$!"
        else
          systemd-inhibit \
            --what=idle:sleep \
            --who="AI Agent" \
            --why="$reason" \
            --mode=block \
            sleep infinity >/dev/null 2>&1 &
          INHIBIT_PID="$!"
        fi
      }

      while true; do
        if has_active_agent; then
          get_battery_pct
          if on_ac_power || (( REPLY >= MIN_BATTERY_PCT )); then
            start_inhibitor
          else
            stop_inhibitor
          fi
          # While an agent is active, wake on session state change OR every 60s
          # to re-verify battery percentage and process liveness.
          inotifywait -qq -t 60 \
            --exclude '(vibe-usage\.cache|claude-quota\.json|\..*\.tmp$)' \
            -e close_write,moved_to,delete "$CLAUDE_DIR" "$VIBE_DIR" || true
        else
          stop_inhibitor
          # When idle, block indefinitely until a session file changes (0 CPU wakeups).
          inotifywait -qq \
            --exclude '(vibe-usage\.cache|claude-quota\.json|\..*\.tmp$)' \
            -e close_write,moved_to,delete "$CLAUDE_DIR" "$VIBE_DIR" || sleep 60
        fi
      done
    '';
  };
in
{
  home.packages = [ agent-sleep-inhibitor ];

  systemd.user.services.agent-sleep-inhibitor = {
    Unit = {
      Description = "Inhibit idle sleep while Claude Code or Mistral Vibe agents are working (on AC or battery >= 30%)";
      After = [ "graphical-session.target" "dbus.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${agent-sleep-inhibitor}/bin/agent-sleep-inhibitor";
      Restart = "always";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "default.target" "graphical-session.target" ];
    };
  };
}
