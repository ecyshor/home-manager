# Delegation tooling used by Claude Code to hand work to Mistral Vibe cheaply:
#   vibe-task  — run a Vibe job from a prompt file; prints only a compact report
#   qrun       — run a verification command quietly; prints a one-line result or the failure tail
{ pkgs, ... }:
let
  # House rules prepended to every write-capable delegated task, so the
  # orchestrating agent only has to write the task-specific spec.
  taskPreamble = pkgs.writeText "vibe-task-preamble.md" ''
    # Delegated task

    You are the implementer. A reviewer will check your diff and your REPORT but will NOT redo your work: finish the whole job yourself.

    ## Rules
    - Work only inside the working directory; never touch other checkouts or worktrees.
    - Complete the task end to end: implementation, tests for new/changed behaviour, and any docs the repo keeps current (README, PLAN.md, AGENTS.md rules, changelogs).
    - Verify before finishing: run the project's FULL test suite plus build / typecheck / lint as documented (README "Testing", AGENTS.md, CI workflow). Fix failures you caused and re-run until green.
    - Never "fix" failures by editing test infrastructure (root conftest.py, pytest.ini, test routing/collection, CI config) or by skipping, xfailing or deleting tests, unless the task explicitly asks for it.
    - Do not run `vibe` or `claude`.
    - Long-running servers: start them fully detached with `setsid -f bash -c '<cmd> </dev/null >/tmp/<name>.log 2>&1'`; never `cmd &`. Never `pkill -f`/`pgrep -f` with a literal pattern (use `[u]vicorn` style or a PID).
    - Do not commit, push or switch branches unless the task explicitly says so.
    - Do not ask questions: make the most reasonable assumption and list it under ASSUMPTIONS.
    - Keep tool output small (`-q`, `| tail -n 40`, `head`) so your context stays focused.

    ## Final message
    End your final message with exactly this section (max 30 lines, no diff dumps):

    ## REPORT
    STATUS: done | partial | blocked
    CHANGED: <path> — <one line> (one line per file)
    VERIFIED: <command> → <result with pass/fail counts> (one line per command)
    ASSUMPTIONS: <list or "none">
    OPEN: <anything unfinished, failing, risky or needing reviewer attention, or "none">

    ---

    # Task

  '';

  followupPreamble = pkgs.writeText "vibe-task-followup.md" ''
    # Reviewer follow-up (same task, same rules as before)

    Address every point below, re-run the relevant verification (full suite if code changed), and end with the same `## REPORT` section.

    ---

  '';

  readonlyPreamble = pkgs.writeText "vibe-task-readonly.md" ''
    # Read-only investigation

    Do NOT modify, create or delete any files and do not start servers. Explore the code and answer the question below.
    Be concise: concrete file paths with line numbers, function/type names, and short explanations. No large code dumps.

    End your final message with:

    ## REPORT
    ANSWER: <concise answer, max 40 lines>
    FILES: <path:line — why it matters> (one per line)
    OPEN: <uncertainties or "none">

    ---

    # Question

  '';

  vibe-task = pkgs.writeShellApplication {
    name = "vibe-task";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.git
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      usage() {
        printf '%s\n' \
          "Usage: vibe-task NAME [options]" \
          "" \
          "Runs Mistral Vibe on the prompt in /tmp/vibe-NAME-prompt.txt (write it first)," \
          "logs everything to /tmp/vibe-NAME.log and prints only a compact summary:" \
          "exit status, session, tokens, git changes and Vibe's final '## REPORT'." \
          "" \
          "Options:" \
          "  --dir DIR         working directory (default: current directory)" \
          "  --resume          continue NAME's previous Vibe session with the prompt file as" \
          "                    reviewer follow-up (Vibe keeps its context; keep the prompt short)" \
          "  --readonly        read-only investigation (Vibe 'plan' agent, no file changes)" \
          "  --timeout SECS    hard timeout (default 1800)" \
          "  --max-price USD   stop the session when it costs more than USD" \
          "  --max-turns N     stop after N assistant turns (counts resumed turns too)" >&2
        exit 2
      }

      [[ $# -ge 1 ]] || usage
      NAME="$1"; shift
      [[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "vibe-task: NAME must match [A-Za-z0-9._-]+" >&2; exit 2; }

      DIR="$PWD"; RESUME=0; READONLY=0; TIMEOUT=1800; EXTRA=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --dir) DIR="$2"; shift 2 ;;
          --resume) RESUME=1; shift ;;
          --readonly) READONLY=1; shift ;;
          --timeout) TIMEOUT="$2"; shift 2 ;;
          --max-price) EXTRA+=(--max-price "$2"); shift 2 ;;
          --max-turns) EXTRA+=(--max-turns "$2"); shift 2 ;;
          -h|--help) usage ;;
          *) echo "vibe-task: unknown option $1" >&2; usage ;;
        esac
      done

      DIR="$(cd "$DIR" && pwd)"
      PROMPT_FILE="/tmp/vibe-$NAME-prompt.txt"
      LOG="/tmp/vibe-$NAME.log"
      SESSION_FILE="/tmp/vibe-$NAME.session"
      FULL_PROMPT="/tmp/vibe-$NAME-full-prompt.txt"

      [[ -s "$PROMPT_FILE" ]] || { echo "vibe-task: write the task to $PROMPT_FILE first" >&2; exit 2; }

      if (( READONLY )); then
        cat ${readonlyPreamble} "$PROMPT_FILE" > "$FULL_PROMPT"
        EXTRA+=(--agent plan)
      elif (( RESUME )); then
        cat ${followupPreamble} "$PROMPT_FILE" > "$FULL_PROMPT"
      else
        cat ${taskPreamble} "$PROMPT_FILE" > "$FULL_PROMPT"
      fi
      if (( RESUME )); then
        [[ -s "$SESSION_FILE" ]] || { echo "vibe-task: no previous session for $NAME ($SESSION_FILE)" >&2; exit 2; }
        EXTRA+=(--resume "$(cat "$SESSION_FILE")")
      fi
      if (( $(wc -c < "$FULL_PROMPT") > 120000 )); then
        echo "vibe-task: prompt too large (>120KB); reference files by path instead of inlining them" >&2
        exit 2
      fi

      IN_GIT=0; TOP="$DIR"; BEFORE=""
      if git -C "$DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
        IN_GIT=1
        TOP="$(git -C "$DIR" rev-parse --show-toplevel)"
        BEFORE="$(git -C "$DIR" rev-parse HEAD 2>/dev/null || true)"
      fi

      # One write-capable Vibe job per tree: concurrent jobs revert each other's edits.
      if (( ! READONLY )); then
        LOCK_DIR="''${XDG_RUNTIME_DIR:-/tmp}/vibe-task"
        mkdir -p "$LOCK_DIR"
        LOCK="$LOCK_DIR/$(printf '%s' "$TOP" | sha1sum | cut -c1-16).lock"
        exec 9>"$LOCK"
        if ! flock -n 9; then
          echo "vibe-task: another Vibe job is already running in $TOP — run sequentially or use a separate worktree" >&2
          exit 3
        fi
      fi

      START="$(date +%s)"
      set +e
      timeout -k 10 "$TIMEOUT" vibe --trust --auto-approve --workdir "$DIR" --output streaming \
        "''${EXTRA[@]}" -p "$(cat "$FULL_PROMPT")" </dev/null >"$LOG" 2>&1
      RC=$?
      set -e
      DUR=$(( $(date +%s) - START ))

      SID="$(jq -rR 'fromjson? | .sessionId // empty' "$LOG" | tail -n 1)"
      [[ -n "$SID" ]] && printf '%s\n' "$SID" > "$SESSION_FILE"

      case "$RC" in
        0) STATUS="ok" ;;
        124|137) STATUS="TIMEOUT after ''${TIMEOUT}s" ;;
        *) STATUS="exit $RC" ;;
      esac
      echo "== vibe-task $NAME: $STATUS ($(( DUR / 60 ))m$(( DUR % 60 ))s) log=$LOG"

      if [[ -n "$SID" ]]; then
        META="$(find "''${VIBE_HOME:-$HOME/.vibe}/logs/session" -maxdepth 2 -path "*_''${SID:0:8}/meta.json" 2>/dev/null | head -n 1 || true)"
        if [[ -n "$META" ]]; then
          jq -r --arg sid "$SID" '.stats as $s |
            "session=\($sid) steps=\($s.steps // 0) tokens=\($s.session_total_llm_tokens // 0) tools_ok=\($s.tool_calls_succeeded // 0) tools_failed=\($s.tool_calls_failed // 0)"' "$META"
        else
          echo "session=$SID"
        fi
      fi

      grep -o '<vibe_stop_event>.*</vibe_stop_event>' "$LOG" | sed 's/<[^>]*>//g; s/^/stop: /' | tail -n 3 || true

      if (( IN_GIT && ! READONLY )); then
        echo "== changes"
        if [[ -n "$BEFORE" ]]; then
          NEW_COMMITS="$(git -C "$DIR" rev-list --count "$BEFORE"..HEAD 2>/dev/null || echo 0)"
          (( NEW_COMMITS > 0 )) && git -C "$DIR" log --oneline "$BEFORE"..HEAD | head -n 10
          git -C "$DIR" diff --stat=120 "$BEFORE" | tail -n 40
        fi
        git -C "$DIR" status --short | grep '^??' | head -n 20 || true
      fi

      echo "== report"
      # Last assistant message only (one JSON-encoded string per message, keep the final one).
      LAST="$(jq -rR 'fromjson?
        | select(.type == "message" and .role == "assistant")
        | (.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end)
        | select(length > 0) | @json' "$LOG" | tail -n 1 | jq -r '.' 2>/dev/null || true)"
      if grep -q '^## REPORT' <<<"$LAST"; then
        sed -n '/^## REPORT/,$p' <<<"$LAST" | head -n 45
      elif [[ -n "$LAST" ]]; then
        echo "(no ## REPORT section; last 30 lines of Vibe's final message)"
        tail -n 30 <<<"$LAST"
      else
        echo "(no assistant message; last tool calls:)"
        jq -rR 'fromjson? | select(.type == "effect") | .detail.display.summary // .title // empty' "$LOG" | tail -n 5 | cut -c1-200
        grep -v '^{' "$LOG" | tail -n 10 | cut -c1-300 || true
      fi
      exit "$RC"
    '';
  };

  qrun = pkgs.writeShellApplication {
    name = "qrun";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      usage() {
        echo "Usage: qrun LABEL [--tail N] -- CMD [ARGS...]   (compound commands: qrun LABEL -- bash -c '...')" >&2
        exit 2
      }
      [[ $# -ge 3 ]] || usage
      LABEL="$1"; shift
      [[ "$LABEL" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "qrun: LABEL must match [A-Za-z0-9._-]+" >&2; exit 2; }
      TAIL=40
      while [[ $# -gt 0 && "$1" != "--" ]]; do
        case "$1" in
          --tail) TAIL="$2"; shift 2 ;;
          *) usage ;;
        esac
      done
      [[ "''${1:-}" == "--" ]] || usage
      shift
      [[ $# -ge 1 ]] || usage

      LOG="/tmp/qrun-$LABEL.log"
      START="$(date +%s)"
      set +e
      "$@" </dev/null >"$LOG" 2>&1
      RC=$?
      set -e
      DUR=$(( $(date +%s) - START ))
      SUMMARY="$(grep -v '^[[:space:]]*$' "$LOG" | tail -n 1 | cut -c1-200 || true)"

      if (( RC == 0 )); then
        echo "ok $LABEL (''${DUR}s) — $SUMMARY"
        exit 0
      fi
      echo "FAIL $LABEL exit=$RC (''${DUR}s) log=$LOG"
      MATCHES="$(grep -nE '(^FAILED|^ERROR|[0-9]+ (failed|errors?)\b|error TS[0-9]+|Error:|✗|✘|panicked)' "$LOG" | head -n 20 || true)"
      if [[ -n "$MATCHES" ]]; then
        echo "-- matches"
        printf '%s\n' "$MATCHES" | cut -c1-300
      fi
      echo "-- last $TAIL lines"
      tail -n "$TAIL" "$LOG" | cut -c1-300
      exit "$RC"
    '';
  };
in
{
  home.packages = [
    vibe-task
    qrun
  ];
}
