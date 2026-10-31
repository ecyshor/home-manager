{ pkgs, git, ... }:
let
  claude-quota-refresh = pkgs.writeShellApplication {
    name = "claude-quota-refresh";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
      CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/claude-sessions"
      mkdir -p "$STATE_DIR" "$CACHE_DIR"

      LOCK_FILE="$STATE_DIR/.quota-refresh.lock"
      NOW="$(date +%s)"
      if [[ -f "$LOCK_FILE" ]]; then
        lock_age=$(( NOW - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
        if (( lock_age < 60 )); then
          exit 0
        fi
      fi
      touch "$LOCK_FILE"
      trap 'rm -f "$LOCK_FILE"' EXIT

      EVENT_JSON="$(
        CLAUDE_QUOTA_PROBE=1 claude -p "ok" \
          --output-format stream-json \
          --verbose \
          --max-turns 1 \
          --model haiku \
          --no-session-persistence 2>/dev/null \
          | jq -c 'select(.type == "rate_limit_event")' \
          | tail -n 1 || true
      )"

      if [[ -n "$EVENT_JSON" ]]; then
        TMP_QUOTA="$CACHE_DIR/.claude-quota.json.tmp"
        jq \
          --argjson updated_at "$(date +%s)" \
          '{
            five_hour_pct: ((.rate_limit_info.unifiedWindows.five_hour.utilization // 0) * 100 | round),
            five_hour_resets_at: (.rate_limit_info.unifiedWindows.five_hour.resetsAt // null),
            seven_day_pct: ((.rate_limit_info.unifiedWindows.seven_day.utilization // 0) * 100 | round),
            seven_day_resets_at: (.rate_limit_info.unifiedWindows.seven_day.resetsAt // null),
            updated_at: $updated_at
          }' <<< "$EVENT_JSON" > "$TMP_QUOTA"
        mv -f "$TMP_QUOTA" "$CACHE_DIR/claude-quota.json"
        cp -f "$CACHE_DIR/claude-quota.json" "$STATE_DIR/claude-quota.json"
      fi
    '';
  };

  claude-statusline = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
      CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/claude-sessions"
      mkdir -p "$STATE_DIR" "$CACHE_DIR"

      INPUT="$(cat)"
      if [[ -z "$INPUT" ]]; then
        exit 0
      fi

      NOW="$(date +%s)"

      # Persist rate_limits whenever Claude Code reports them
      if jq -e '.rate_limits != null' >/dev/null 2>&1 <<< "$INPUT"; then
        TMP_QUOTA="$CACHE_DIR/.claude-quota.json.tmp"
        jq \
          --argjson updated_at "$NOW" \
          '{
            five_hour_pct: (.rate_limits.five_hour.used_percentage // null),
            five_hour_resets_at: (.rate_limits.five_hour.resets_at // null),
            seven_day_pct: (.rate_limits.seven_day.used_percentage // null),
            seven_day_resets_at: (.rate_limits.seven_day.resets_at // null),
            spend_pct: (.rate_limits.spend_limit.used_percentage // null),
            spend_used_usd: (.rate_limits.spend_limit.used_usd // null),
            spend_limit_usd: (.rate_limits.spend_limit.limit_usd // null),
            session_cost_usd: (.cost.total_cost_usd // null),
            updated_at: $updated_at
          }' <<< "$INPUT" > "$TMP_QUOTA"
        mv -f "$TMP_QUOTA" "$CACHE_DIR/claude-quota.json"
        cp -f "$CACHE_DIR/claude-quota.json" "$STATE_DIR/claude-quota.json"
      fi

      # Render a clean status line inside the Claude Code TUI
      jq -r '
        def pct(v): if v == null then "" else ((v | round | tostring) + "%") end;
        "[ " + (.model.display_name // "Claude") + " ] " +
        "📁 " + ((.workspace.current_dir // "") | split("/") | last) +
        (if .context_window.used_percentage != null then " │ ctx:" + pct(.context_window.used_percentage) else "" end) +
        (if .rate_limits.five_hour.used_percentage != null then " │ 5h:" + pct(.rate_limits.five_hour.used_percentage) else "" end) +
        (if .rate_limits.seven_day.used_percentage != null then " 7d:" + pct(.rate_limits.seven_day.used_percentage) else "" end)
      ' <<< "$INPUT"
    '';
  };

  claude-session-hook = pkgs.writeShellApplication {
    name = "claude-session-hook";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.libnotify
      pkgs.procps
      pkgs.tmux
      claude-quota-refresh
    ];
    text = ''
      if [[ "''${CLAUDE_QUOTA_PROBE:-}" == "1" ]]; then
        exit 0
      fi

      STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
      CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/claude-sessions"
      mkdir -p "$STATE_DIR" "$CACHE_DIR"

      INPUT="$(cat)"
      if [[ -z "$INPUT" ]]; then
        exit 0
      fi

      SESSION_ID="$(jq -r '.session_id // empty' <<< "$INPUT")"
      if [[ -z "$SESSION_ID" ]]; then
        exit 0
      fi

      EVENT="$(jq -r '.hook_event_name // empty' <<< "$INPUT")"
      CWD="$(jq -r '.cwd // empty' <<< "$INPUT")"

      if [[ "$EVENT" == "SessionEnd" ]]; then
        rm -f "$STATE_DIR/$SESSION_ID.json"
        exit 0
      fi

      # Walk up process tree from $PPID to find the long-lived `claude` process
      CLAUDE_PID="$PPID"
      curr="$PPID"
      for _ in 1 2 3 4 5 6; do
        if [[ ! -r "/proc/$curr/comm" ]]; then
          break
        fi
        comm="$(tr -d '\0\n' < "/proc/$curr/comm" || true)"
        if [[ "$comm" == "claude" || "$comm" == ".claude-wrapped" ]]; then
          CLAUDE_PID="$curr"
          break
        fi
        next_ppid="$(awk '/^PPid:/ { print $2 }' "/proc/$curr/status" 2>/dev/null || true)"
        if [[ -z "$next_ppid" || "$next_ppid" -le 1 ]]; then
          break
        fi
        curr="$next_ppid"
      done

      STATE="idle"
      DETAIL=""
      case "$EVENT" in
        SessionStart)
          STATE="idle"
          DETAIL="Session started"
          ;;
        UserPromptSubmit)
          STATE="working"
          DETAIL="Thinking / planning"
          ;;
        PreToolUse)
          STATE="working"
          TOOL="$(jq -r '.tool_name // "tool"' <<< "$INPUT")"
          DETAIL="Running $TOOL"
          ;;
        PostToolUse)
          STATE="working"
          TOOL="$(jq -r '.tool_name // "tool"' <<< "$INPUT")"
          DETAIL="Completed $TOOL"
          ;;
        Notification)
          NTYPE="$(jq -r '.notification_type // ""' <<< "$INPUT")"
          MSG="$(jq -r '.message // "Needs input"' <<< "$INPUT")"
          if [[ "$NTYPE" == "idle_prompt" ]]; then
            STATE="idle"
          else
            STATE="waiting"
          fi
          DETAIL="$MSG"
          # Desktop notifications disabled; state is tracked via the status bar.
          ;;
        Stop)
          STATE="idle"
          DETAIL="Idle (turn complete)"
          ;;
        *)
          STATE="idle"
          DETAIL="$EVENT"
          ;;
      esac

      # Refresh quota in background on SessionStart or Stop if missing or older than 5 min
      if [[ "$EVENT" == "SessionStart" || "$EVENT" == "Stop" ]]; then
        qfile="$CACHE_DIR/claude-quota.json"
        now_ts="$(date +%s)"
        q_age=999999
        if [[ -f "$qfile" ]]; then
          q_age=$(( now_ts - $(stat -c %Y "$qfile" 2>/dev/null || echo 0) ))
        fi
        if (( q_age > 300 )); then
          nohup claude-quota-refresh >/dev/null 2>&1 &
        fi
      fi

      TMUX_SOCKET=""
      TMUX_PANE_ID="''${TMUX_PANE:-}"
      TMUX_TARGET=""
      if [[ -n "''${TMUX:-}" ]]; then
        TMUX_SOCKET="''${TMUX%%,*}"
        if [[ -n "$TMUX_PANE_ID" ]]; then
          TMUX_TARGET="$(tmux -S "$TMUX_SOCKET" display-message -p -t "$TMUX_PANE_ID" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)"
        fi
      fi

      NOW="$(date +%s)"
      PROJECT="$(basename "''${CWD:-unknown}")"
      TMP_FILE="$STATE_DIR/.$SESSION_ID.json.tmp"

      jq -n \
        --arg session_id "$SESSION_ID" \
        --arg cwd "$CWD" \
        --arg project "$PROJECT" \
        --arg state "$STATE" \
        --arg detail "$DETAIL" \
        --arg event "$EVENT" \
        --argjson updated_at "$NOW" \
        --argjson pid "$CLAUDE_PID" \
        --arg tmux_socket "$TMUX_SOCKET" \
        --arg tmux_pane "$TMUX_PANE_ID" \
        --arg tmux_target "$TMUX_TARGET" \
        --arg nvim_socket "''${NVIM:-}" \
        '{
          session_id: $session_id,
          cwd: $cwd,
          project: $project,
          state: $state,
          detail: $detail,
          event: $event,
          updated_at: $updated_at,
          pid: $pid,
          tmux_socket: $tmux_socket,
          tmux_pane: $tmux_pane,
          tmux_target: $tmux_target,
          nvim_socket: $nvim_socket
        }' > "$TMP_FILE"

      mv -f "$TMP_FILE" "$STATE_DIR/$SESSION_ID.json"
    '';
  };

  claude-sessions = pkgs.writeShellApplication {
    name = "claude-sessions";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.fzf
      pkgs.gawk
      pkgs.git
      pkgs.gnused
      pkgs.jq
      pkgs.procps
      pkgs.tmux
      claude-quota-refresh
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/claude-sessions"
      VIBE_STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/vibe-sessions"
      CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/claude-sessions"
      mkdir -p "$STATE_DIR" "$VIBE_STATE_DIR" "$CACHE_DIR"

      prune_dead() {
        shopt -s nullglob
        for f in "$STATE_DIR"/*.json "$VIBE_STATE_DIR"/*.json; do
          base="$(basename "$f")"
          [[ "$base" == "claude-quota.json" || "$base" == "vibe-usage.cache" ]] && continue
          pid="$(jq -r '.pid // empty' "$f" 2>/dev/null || true)"
          if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$f"
          fi
        done
      }

      find_session_file() {
        local sid="$1"
        if [[ -f "$STATE_DIR/$sid.json" ]]; then
          echo "$STATE_DIR/$sid.json"
          return
        fi
        if [[ -f "$VIBE_STATE_DIR/$sid.json" ]]; then
          echo "$VIBE_STATE_DIR/$sid.json"
          return
        fi
        shopt -s nullglob
        for vf in "$VIBE_STATE_DIR"/*.json; do
          if [[ "$(jq -r '.session_id // empty' "$vf" 2>/dev/null || true)" == "$sid" ]]; then
            echo "$vf"
            return
          fi
        done
      }

      format_age() {
        local diff=$(( $(date +%s) - $1 ))
        if (( diff < 60 )); then
          printf "%ds" "$diff"
        elif (( diff < 3600 )); then
          printf "%dm" $(( diff / 60 ))
        else
          printf "%dh" $(( diff / 3600 ))
        fi
      }

      # Returns Claude session % + reset time and week % + reset date,
      # e.g. "C:5%(20:00) 7d:3%(Oct 30)"
      get_claude_quota_short() {
        local qfile="$CACHE_DIR/claude-quota.json"
        [[ ! -f "$qfile" && -f "$STATE_DIR/claude-quota.json" ]] && qfile="$STATE_DIR/claude-quota.json"
        if [[ ! -f "$qfile" ]]; then
          nohup claude-quota-refresh >/dev/null 2>&1 &
          echo "C:..."
          return
        fi

        local now p5 r5 p7 r7
        now="$(date +%s)"
        IFS=$'\t' read -r p5 r5 p7 r7 < <(
          jq -r '[
            (if .five_hour_pct == null then "" else (.five_hour_pct | round | tostring) end),
            (if .five_hour_resets_at == null then "" else (.five_hour_resets_at | tostring) end),
            (if .seven_day_pct == null then "" else (.seven_day_pct | round | tostring) end),
            (if .seven_day_resets_at == null then "" else (.seven_day_resets_at | tostring) end)
          ] | @tsv' "$qfile" 2>/dev/null || echo ""
        )

        if [[ -z "$p5" && -z "$p7" ]]; then
          echo "C:--"
          return
        fi

        local s5="--" s7="--"
        if [[ -n "$p5" ]]; then
          if [[ -n "$r5" ]] && (( now >= r5 )); then
            s5="0%"
          elif [[ -n "$r5" ]]; then
            s5="''${p5}%($(date -d "@$r5" +%H:%M 2>/dev/null || echo ""))"
          else
            s5="''${p5}%"
          fi
        fi

        if [[ -n "$p7" ]]; then
          if [[ -n "$r7" ]] && (( now >= r7 )); then
            s7="0%"
          elif [[ -n "$r7" ]]; then
            s7="''${p7}%($(date -d "@$r7" +"%b %-d" 2>/dev/null || echo ""))"
          else
            s7="''${p7}%"
          fi
        fi

        printf "C:%s 7d:%s" "$s5" "$s7"
      }

      # Returns Mistral Vibe monthly usage % out of $300 monthly max usage (cached 15s)
      get_vibe_monthly_stats() {
        local vibe_dir="''${VIBE_HOME:-$HOME/.vibe}/logs/session"
        local month_prefix
        month_prefix="$(date +%Y-%m)"
        local next_reset
        next_reset="$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null || echo "1st")"
        local month_cost="0"
        if [[ -d "$vibe_dir" ]]; then
          shopt -s nullglob
          local meta_files=("$vibe_dir"/session_*/meta.json)
          if (( ''${#meta_files[@]} > 0 )); then
            month_cost="$(jq -rn --arg ym "$month_prefix" '
              [inputs
               | select((.start_time // "") | startswith($ym))
               | .stats
               | if (.session_cost // 0) > 0 then
                   .session_cost
                 else
                   ((((.session_prompt_tokens // 0) - (.session_cached_tokens // 0)) * 1.35)
                    + ((.session_cached_tokens // 0) * 0.135)
                    + ((.session_completion_tokens // 0) * 4.05)) / 1000000
                 end
              ] | add // 0
            ' "''${meta_files[@]}" 2>/dev/null || echo 0)"
          fi
        fi

        local max_usd="''${VIBE_MONTHLY_MAX_USD:-}"
        if [[ -z "$max_usd" && -f "$CACHE_DIR/vibe-quota.json" ]]; then
          max_usd="$(jq -r '.monthly_max_usd // empty' "$CACHE_DIR/vibe-quota.json" 2>/dev/null || true)"
        fi
        [[ -z "$max_usd" ]] && max_usd="300"

        local pct
        pct="$(awk -v c="$month_cost" -v m="$max_usd" 'BEGIN { if (m > 0) printf "%.0f", (c / m) * 100; else print 0 }')"
        printf "%s\t%s\t%s\t%s\n" "$pct" "$month_cost" "$max_usd" "$next_reset"
      }

      get_vibe_quota_short() {
        local vcache="$STATE_DIR/vibe-usage.cache"
        local now
        now="$(date +%s)"
        if [[ -f "$vcache" ]]; then
          local mtime
          mtime="$(stat -c %Y "$vcache" 2>/dev/null || echo 0)"
          if (( now - mtime < 15 )); then
            cat "$vcache"
            return
          fi
        fi

        local pct cost max_usd next_reset
        IFS=$'\t' read -r pct cost max_usd next_reset < <(get_vibe_monthly_stats)
        local formatted="M:''${pct}%((''${next_reset}))"
        formatted="M:''${pct}%(''${next_reset})"
        printf "%s" "$formatted" > "$vcache"
        printf "%s" "$formatted"
      }

      get_quota_header() {
        local c_short pct cost max_usd next_reset
        c_short="$(get_claude_quota_short)"
        IFS=$'\t' read -r pct cost max_usd next_reset < <(get_vibe_monthly_stats)
        awk -v cs="$c_short" -v mp="$pct" -v mc="$cost" -v mm="$max_usd" -v nr="$next_reset" \
          'BEGIN { printf "Quota: %s │ Mistral: %s%% ($%.1f / $%.0f · resets %s)", cs, mp, mc, mm, nr }'
      }

      cmd="''${1:-interactive}"

      case "$cmd" in
        --refresh-quota)
          claude-quota-refresh
          rm -f "$STATE_DIR/vibe-usage.cache"
          claude-sessions --status-bar
          ;;

        --set-vibe-pct)
          target_pct="''${2:-}"
          if [[ -z "$target_pct" ]]; then
            echo "Usage: claude-sessions --set-vibe-pct <percentage_from_mistral_ui>" >&2
            exit 1
          fi
          IFS=$'\t' read -r _ cur_cost _ < <(get_vibe_monthly_stats)
          new_max="$(awk -v c="$cur_cost" -v p="$target_pct" 'BEGIN { if (p > 0) printf "%.4f", (c / (p / 100.0)); else print 25.0 }')"
          jq -n --argjson max "$new_max" '{ monthly_max_usd: $max }' > "$CACHE_DIR/vibe-quota.json"
          rm -f "$STATE_DIR/vibe-usage.cache"
          echo "Calibrated Mistral monthly max to \$$new_max (current usage: ''${target_pct}%)"
          ;;

        --status|--status-bar)
          prune_dead
          shopt -s nullglob
          c_working=0
          c_waiting=0
          c_idle=0
          for f in "$STATE_DIR"/*.json; do
            [[ "$(basename "$f")" == "claude-quota.json" ]] && continue
            st="$(jq -r '.state // "idle"' "$f" 2>/dev/null || echo "idle")"
            case "$st" in
              working) c_working=$((c_working + 1)) ;;
              waiting) c_waiting=$((c_waiting + 1)) ;;
              *)       c_idle=$((c_idle + 1)) ;;
            esac
          done

          v_working=0
          v_waiting=0
          v_idle=0
          for f in "$VIBE_STATE_DIR"/*.json; do
            st="$(jq -r '.state // "idle"' "$f" 2>/dev/null || echo "idle")"
            case "$st" in
              working) v_working=$((v_working + 1)) ;;
              waiting) v_waiting=$((v_waiting + 1)) ;;
              *)       v_idle=$((v_idle + 1)) ;;
            esac
          done

          c_quota="$(get_claude_quota_short)"
          m_quota="$(get_vibe_quota_short)"
          sess_parts=()
          if (( c_working + c_waiting + c_idle > 0 )); then
            c_sess="🤖"
            (( c_working > 0 )) && c_sess+=" ''${c_working}⚡"
            (( c_waiting > 0 )) && c_sess+=" ''${c_waiting}🔔"
            (( c_idle > 0 ))    && c_sess+=" ''${c_idle}💤"
            sess_parts+=("$c_sess")
          fi
          if (( v_working + v_waiting + v_idle > 0 )); then
            v_sess="🌀"
            (( v_working > 0 )) && v_sess+=" ''${v_working}⚡"
            (( v_waiting > 0 )) && v_sess+=" ''${v_waiting}🔔"
            (( v_idle > 0 ))    && v_sess+=" ''${v_idle}💤"
            sess_parts+=("$v_sess")
          fi

          if (( ''${#sess_parts[@]} > 0 )); then
            sess="''${sess_parts[*]}"
            printf "%s │ %s │ %s\n" "$sess" "$c_quota" "$m_quota"
          else
            printf "%s │ %s\n" "$c_quota" "$m_quota"
          fi
          ;;

        --list)
          prune_dead
          shopt -s nullglob
          files=()
          for f in "$STATE_DIR"/*.json "$VIBE_STATE_DIR"/*.json; do
            [[ "$(basename "$f")" == "claude-quota.json" ]] && continue
            files+=("$f")
          done
          if (( ''${#files[@]} == 0 )); then
            exit 0
          fi
          # Sort order: waiting (1), working (2), idle (3), then newest updated_at first
          jq -rn '
            def rank: if .state == "waiting" then 1 elif .state == "working" then 2 else 3 end;
            [inputs] | sort_by(rank, -(.updated_at // 0))[] |
            [
              (.session_id // (.pid | tostring)),
              (.agent // "claude"),
              (.state // "idle"),
              (.project // ((.cwd // "unknown") | split("/") | last)),
              ((.updated_at // 0) | tostring),
              (.detail // (.state // "idle")),
              (.cwd // ""),
              (.tmux_target // ""),
              (.nvim_socket // "")
            ] | @tsv
          ' "''${files[@]}" | while IFS=$'\t' read -r sid agent state project updated detail cwd tmux_target nvim_sock; do
            age="$(format_age "$updated")"
            icon="🤖"
            [[ "$agent" == "vibe" ]] && icon="🌀"
            case "$state" in
              working) badge="$icon "$'\033[1;33m⚡ working\033[0m' ;;
              waiting) badge="$icon "$'\033[1;31m🔔 waiting\033[0m' ;;
              *)       badge="$icon "$'\033[0;36m💤 idle   \033[0m' ;;
            esac
            host_tag="term"
            [[ -n "$tmux_target" ]] && host_tag="tmux:$tmux_target"
            [[ -n "$nvim_sock" ]] && host_tag="nvim:$host_tag"
            printf "%s\t%s  %-22s  \033[0;90m(%4s ago)\033[0m  %-26s  \033[0;90m[%s] %s\033[0m\n" \
              "$sid" "$badge" "$project" "$age" "$detail" "$host_tag" "$cwd"
          done
          ;;

        --preview)
          sid="''${2:-}"
          f="$(find_session_file "$sid")"
          printf "\033[1;36m%s\033[0m\n" "$(get_quota_header)"
          echo "--------------------------------------------------------"
          if [[ -z "$f" || ! -f "$f" ]]; then
            echo "Session no longer active."
            exit 0
          fi
          IFS=$'\t' read -r p_agent p_project p_state p_cwd p_detail p_pid p_updated p_tmux_sock p_tmux_pane p_tmux_target p_nvim_sock < <(
            jq -r '[
              (.agent // "claude"),
              (.project // ((.cwd // "") | split("/") | last)),
              (.state // ""),
              (.cwd // ""),
              (.detail // ""),
              (.pid | tostring),
              (.updated_at | tostring),
              (.tmux_socket // ""),
              (.tmux_pane // ""),
              (.tmux_target // ""),
              (.nvim_socket // "")
            ] | @tsv' "$f"
          )
          age="$(format_age "$p_updated")"
          agent_label="🤖 Claude Code"
          [[ "$p_agent" == "vibe" ]] && agent_label="🌀 Mistral Vibe"
          printf "\033[1;34mAgent:\033[0m     %s\n" "$agent_label"
          printf "\033[1;34mProject:\033[0m   %s\n" "$p_project"
          printf "\033[1;34mWorkspace:\033[0m %s\n" "$p_cwd"
          printf "\033[1;34mState:\033[0m     %s (%s ago) - %s\n" "$p_state" "$age" "$p_detail"
          printf "\033[1;34mPID:\033[0m       %s\n" "$p_pid"
          [[ -n "$p_tmux_target" ]] && printf "\033[1;34mTmux:\033[0m      %s (%s)\n" "$p_tmux_target" "$p_tmux_sock"
          [[ -n "$p_nvim_sock" ]]   && printf "\033[1;34mNeovim:\033[0m    %s\n" "$p_nvim_sock"
          echo "--------------------------------------------------------"
          if [[ -n "$p_tmux_sock" && -n "$p_tmux_pane" ]] && tmux -S "$p_tmux_sock" has-session -t "$p_tmux_pane" 2>/dev/null; then
            printf "\033[1;32mLive Terminal Pane Preview:\033[0m\n"
            tmux -S "$p_tmux_sock" capture-pane -ep -t "$p_tmux_pane" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 24
            echo "--------------------------------------------------------"
          fi
          if [[ -d "$p_cwd/.git" ]] || git -C "$p_cwd" rev-parse --git-dir >/dev/null 2>&1; then
            printf "\033[1;35mGit Status:\033[0m\n"
            git -C "$p_cwd" -c color.status=always status -sb 2>/dev/null | head -n 15
          fi
          ;;

        --jump)
          sid="''${2:-}"
          f="$(find_session_file "$sid")"
          [[ -z "$f" || ! -f "$f" ]] && exit 0
          IFS=$'\t' read -r j_agent j_cwd j_tmux_sock j_tmux_pane j_tmux_target < <(
            jq -r '[
              (.agent // "claude"),
              (.cwd // ""),
              (.tmux_socket // ""),
              (.tmux_pane // ""),
              (.tmux_target // "")
            ] | @tsv' "$f"
          )
          if [[ -n "$j_tmux_sock" && -n "$j_tmux_pane" ]] && tmux -S "$j_tmux_sock" has-session -t "$j_tmux_pane" 2>/dev/null; then
            win_target="''${j_tmux_target%.*}"
            tmux -S "$j_tmux_sock" select-window -t "$win_target" 2>/dev/null || true
            tmux -S "$j_tmux_sock" select-pane -t "$j_tmux_pane" 2>/dev/null || true
            current_sock="''${TMUX%%,*}"
            if [[ -n "''${TMUX:-}" && "$current_sock" == "$j_tmux_sock" ]]; then
              tmux -S "$j_tmux_sock" switch-client -t "$win_target" 2>/dev/null || true
            elif [[ -z "''${TMUX:-}" ]]; then
              exec tmux -S "$j_tmux_sock" attach-session -t "''${j_tmux_target%%:*}"
            fi
          elif [[ -d "$j_cwd" ]]; then
            cd "$j_cwd"
            if [[ "$j_agent" == "vibe" ]]; then
              exec vibe --resume "$sid"
            else
              exec claude --resume "$sid"
            fi
          fi
          ;;

        --delete)
          sid="''${2:-}"
          f="$(find_session_file "$sid")"
          [[ -n "$f" ]] && rm -f "$f"
          ;;

        *)
          header="$(get_quota_header)  ──  Enter: jump │ Ctrl-R: refresh │ Ctrl-X: dismiss"
          selected="$(
            claude-sessions --list | fzf \
              --ansi \
              --delimiter=$'\t' \
              --with-nth=2.. \
              --header="$header" \
              --prompt="Claude Sessions > " \
              --preview="claude-sessions --preview {1}" \
              --preview-window="right:55%:wrap" \
              --bind="ctrl-r:reload(claude-sessions --list)" \
              --bind="ctrl-x:execute-silent(claude-sessions --delete {1})+reload(claude-sessions --list)" \
              --no-info || true
          )"
          if [[ -n "$selected" ]]; then
            sid="''${selected%%$'\t'*}"
            exec claude-sessions --jump "$sid"
          fi
          ;;
      esac
    '';
  };

  hookEntry = [
    {
      hooks = [
        {
          type = "command";
          command = "${claude-session-hook}/bin/claude-session-hook";
        }
      ];
    }
  ];
  # Pinned plugin sources (update: `nix flake prefetch github:<owner>/<repo>/<rev>` → rev + hash)
  claude-plugins-official = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-plugins-official";
    rev = "a7ba5b93db0c7c8d17f3f1d25853adca79598a1a";
    hash = "sha256-C8uTRCtKEvL7dz+dDbfs/DwU/uxH5YzYFDn0oo3BKnA=";
  };

  shipSkill = ''
    ---
    name: ship
    description: Commit, merge the latest origin/main, verify, push and merge to main, then make sure local servers and CI are current. Use when the user says "commit and merge", "commit, push", "push everything", "merge to main", "make sure everything is committed pushed and merged", or "check the status".
    ---

    # Ship: commit → merge origin/main → verify → push → main

    Work only in the current checkout/worktree (worktree sessions refuse `git -C` or `cd` into other checkouts).

    ## 1. Commit
    - `git status --short`; read every uncommitted change before committing (Vibe may have touched unrelated files, conftest.py or pytest.ini — revert those unless intended).
    - If the repo has AGENTS.md rules (e.g. keep PLAN.md / README.md current), make sure the docs match the change.
    - Commit with `git commit -s` (identity Nicu Reut <contact@nicu.dev>). Never add AI co-author lines, AI sign-offs or "Generated with" footers.
    - Check every unpushed commit: `git log --format='%h %s%n%(trailers)' origin/main..HEAD`. Exactly one `Signed-off-by: Nicu Reut <contact@nicu.dev>`, no `Co-Authored-By`. If an unpushed commit is wrong, rewrite it (non-interactive: `GIT_SEQUENCE_EDITOR=true git rebase <base> --exec <script that amends the message>`), then confirm the tree is unchanged with `git diff --stat <old-head> HEAD`. Never rewrite pushed commits.

    ## 2. Fetch + merge origin/main
    - SSH push/fetch usually has no key here; use HTTPS with gh's credential helper. Repo URL from `git remote get-url origin` (git@github.com:OWNER/REPO.git → https://github.com/OWNER/REPO.git):
      `git -c credential.helper='!gh auth git-credential' fetch https://github.com/OWNER/REPO.git +refs/heads/main:refs/remotes/origin/main`
    - `git rev-list --left-right --count origin/main...HEAD`; if origin/main has new commits, `git merge --no-edit origin/main`.
    - Conflicts: docs (PLAN.md, README.md, changelogs) usually keep both sides; code: read both sides, keep both behaviours. Commit the merge with `git commit --no-edit -s`.
    - After merging, think about how the incoming features interact with this branch's (new tables/columns, filters, hooks) — not only textual conflicts. Fix and test integration gaps before pushing.

    ## 3. Verify (never push red)
    - Run the project's full test suite and builds (README "Testing", AGENTS.md, CI workflow); if the repo ships a project skill for dev/test/run (e.g. `.claude/skills/*-dev`), use it.
    - Update any "last verified" test counts in the docs if the repo keeps them.

    ## 4. Push + merge to main
    - Fast-forward only: push the branch and main in one go:
      `git -c credential.helper='!gh auth git-credential' push https://github.com/OWNER/REPO.git HEAD:refs/heads/BRANCH HEAD:refs/heads/main`
    - If the push is rejected (main moved), go back to step 2. Never force-push main.
    - A local `main` checked out in another folder may hold another session's unpushed commits: don't touch it; report it instead.

    ## 5. After pushing
    - Local servers: if a backend / dev server runs from this checkout, make sure it serves the new code (see the repo's dev/run skill if it has one); report what was restarted.
    - CI: `gh run list --branch main --limit 5`; watch the new run (`gh run watch <id> --exit-status`) when the user asked for green CI, and fix failures even if unrelated.

    ## 6. Report
    Commits pushed (short SHAs + subjects), what was merged in, conflicts and how they were resolved, test/build results with counts, anything left (other checkouts' unpushed commits, skipped steps).
  '';
in
{
  home.packages = [
    claude-quota-refresh
    claude-statusline
    claude-session-hook
    claude-sessions
  ];

  programs.claude-code = {
    enable = true;
    mutableSettings = true;

    # Plugins pinned in Nix (symlinked as personal plugins; bump rev + hash to update)
    plugins = {
      frontend-design = "${claude-plugins-official}/plugins/frontend-design";
      security-guidance = "${claude-plugins-official}/plugins/security-guidance";
    };

    # Code intelligence (replaces the pyright-lsp / typescript-lsp marketplace plugins)
    lspServers = {
      pyright = {
        command = "${pkgs.pyright}/bin/pyright-langserver";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".py" = "python";
          ".pyi" = "python";
        };
      };
      typescript = {
        command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".ts" = "typescript";
          ".tsx" = "typescriptreact";
          ".js" = "javascript";
          ".jsx" = "javascriptreact";
          ".mts" = "typescript";
          ".cts" = "typescript";
          ".mjs" = "javascript";
          ".cjs" = "javascript";
        };
      };
    };

    # Browser automation (replaces the playwright marketplace plugin's `npx @playwright/mcp@latest`;
    # the nixpkgs build ships its own Chromium)
    mcpServers.playwright = {
      type = "stdio";
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
    };

    skills = {
      ship = shipSkill;
    };

    settings = {
      theme = "dark";
      permissions = {
        blockReadsOutsideWorkingDirectories = false;
        # Delegation + cheap verification run without permission prompts
        allow = [
          "Bash(vibe-task:*)"
          "Bash(qrun:*)"
          "Bash(git status:*)"
          "Bash(git diff:*)"
          "Bash(git log:*)"
          "Bash(git show:*)"
        ];
      };
      env = {
        # Subagents (Explore etc.) do grunt work; keep them off Opus
        CLAUDE_CODE_SUBAGENT_MODEL = "haiku";
        # Cap accidental log / test / diff dumps into the context
        BASH_MAX_OUTPUT_LENGTH = "12000";
        # Mild context cap: keep the 1M model but auto-compact around ~300k tokens
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = "300000";
      };
      statusLine = {
        type = "command";
        command = "${claude-statusline}/bin/claude-statusline";
        padding = 0;
      };
      hooks = {
        SessionStart = hookEntry;
        UserPromptSubmit = hookEntry;
        PreToolUse = hookEntry;
        PostToolUse = hookEntry;
        Notification = hookEntry;
        Stop = hookEntry;
        SessionEnd = hookEntry;
      };
      # No Claude co-author trailers / "Generated with Claude Code" footers.
      attribution = {
        commit = "";
        pr = "";
      };
      includeCoAuthoredBy = false;
    };

    # Global instructions (~/.claude/CLAUDE.md): Claude Code orchestrates & reviews,
    # delegating all implementation, test execution, debugging, and docs to Mistral Vibe (`vibe-task`).
    context = ''
      # Strict Delegation Workflow: Claude Code Orchestrates, Mistral Vibe Implements & Tests

      Act strictly as the lead architect, specification writer, and code reviewer.
      To minimize Claude token consumption, delegate all heavy lifting and grunt work to **Mistral Vibe** (`vibe-task`), including:
      - Writing and editing code, boilerplate, refactorings, migrations
      - Running test suites, typechecks, linters, and debugging test failures until green
      - Updating documentation (PLAN.md, README.md, AGENTS.md status, changelogs)
      - Starting/restarting background daemons and running curl/API smoke checks
      - Investigating codebases for "how does X work" or "where is Y defined"

      ## 1. Plan & Specify (Claude Code)
      - Explore files lightly if needed, or run `vibe-task <name> --readonly` for broad code investigations to keep Claude's context small.
      - Formulate a clear, self-contained specification: target files, function signatures, constraints, and testing expectations.
      - Write the prompt directly to `/tmp/vibe-<task>-prompt.txt` using the Write tool (do not use complex bash heredocs that trip shell guards). Note that `vibe-task` automatically prepends standard house rules (commit policies, test rules, detached daemon rules, and the final `## REPORT` format requirement).

      ## 2. Delegate to Mistral Vibe (`vibe-task`)
      - Run the task non-interactively via the `vibe-task` helper:
        ```bash
        vibe-task <task> --dir <dir>
        ```
      - **Always launch long-running or parallel tasks with `run_in_background: true`** via the Bash tool. DO NOT poll in a loop with `sleep`, `tail`, `until`, or periodic log reads—each polling turn wastes thousands of context tokens. Wait for the background task completion notification.
      - If Vibe needs to address review findings, update `/tmp/vibe-<task>-prompt.txt` with concise feedback and run with `--resume`:
        ```bash
        vibe-task <task> --resume --dir <dir>
        ```
        This continues Vibe's previous session with full context, avoiding re-explaining the whole task.

      ## 3. Validate & Review Output (Claude Code)
      - `vibe-task` automatically suppresses noisy tool logs and outputs:
        1. Exit status, duration, and token usage
        2. `git diff --stat`
        3. Vibe's structured `## REPORT` (status, changed files, test verification results, assumptions, open items)
      - **Review the diff**: Check `git status --short` and inspect only the relevant diffs (`git diff -- <file>`) to verify correctness, regressions, and style.
      - **Quick validation**: If you want to independently verify Vibe's claims, use `qrun` to execute tests/builds quietly without polluting Claude's context with thousands of lines:
        ```bash
        qrun check-tests -- pytest -q
        ```
        `qrun` outputs only a single summary line on success, or the failure tail on error.
      - Edit files directly ONLY for trivial <= 5 line fixes discovered during review. If larger adjustments are needed, send them back to Vibe via `vibe-task <task> --resume`.
    '' + "\n" + import ./agent-commit-policy.nix git;

    # Custom subagent (~/.claude/agents/mistral-vibe.md) for handing off implementation tasks.
    agents.mistral-vibe = ''
      ---
      name: mistral-vibe
      description: Delegates implementation, test execution, debugging, and file edits to Mistral Vibe (`vibe-task`). Use this subagent to offload coding work and receive a concise diff report.
      tools: Bash, Read, Grep, Glob
      model: haiku
      omitClaudeMd: true
      ---

      You are a lightweight subagent wrapper running on Haiku. Your role is to trigger `vibe-task` to execute implementation tasks planned by the main agent and report the results back.

      ## Execution Steps
      1. Ensure the task prompt is written to `/tmp/vibe-<task>-prompt.txt`.
      2. Run `vibe-task <task> --dir <dir>` (or with `--resume` if continuing an earlier task).
      3. Report the exit status, changed files, and the `## REPORT` summary block directly back to the parent agent. Do not re-implement or modify code yourself.
    '';
  };
}
