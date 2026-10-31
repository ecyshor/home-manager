{ pkgs, git, ... }: {
  home.file.".vibe/config.toml".force = true;
  home.file.".vibe/AGENTS.md" = {
    force = true;
    text = ''
      # Default User Instructions

      ## New Project Setup: Nix Flakes + direnv (`nix/flake.nix` + `.envrc`)

      Whenever creating or initializing **any new project** (or setting up an environment for a project that does not have one yet), always set up **direnv + Nix with Flakes** inside a `nix/` subdirectory (following the layout from https://nicu.dev/dirnev-nix-shell adapted to Flakes) and include all required project dependencies:

      1. **Create `nix/flake.nix`** with all required project dependencies (language runtimes, compilers, package managers, build tools, linters, native libraries, etc.) in `pkgs.mkShell`:
         ```nix
         {
           description = "Development environment";

           inputs = {
             nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
           };

           outputs = { self, nixpkgs }:
             let
               supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
               forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
             in
             {
               devShells = forAllSystems (system:
                 let
                   pkgs = import nixpkgs { inherit system; };
                 in
                 {
                   default = pkgs.mkShell {
                     buildInputs = with pkgs; [
                       # Include all needed project dependencies here
                     ];
                   };
                 }
               );
             };
         }
         ```
      2. **Create `.envrc` in the project root** to watch and load `nix/flake.nix`:
         ```bash
         #!/usr/bin/env bash

         watch_file nix/flake.nix
         watch_file nix/flake.lock

         use flake ./nix
         ```
      3. **Git tracking & activation**:
         - Add `.direnv/` to `.gitignore`.
         - If the project is a Git repository, stage `nix/flake.nix` (`git add nix/flake.nix`) before evaluating the flake (Nix Flakes ignores untracked files in a Git repo).
         - Run `direnv allow` and verify the environment loads cleanly (e.g. via `direnv exec . <cmd>` or `nix develop ./nix -c <cmd>`).
         - Whenever additional tools or dependencies are needed, add them to `nix/flake.nix` under `buildInputs`.

      ## Background Daemons & Process Management

      - **Detaching long-running servers/daemons**: Never start or restart a background server or daemon (e.g. `uvicorn`, `vite`, dev servers) with standard backgrounding (`cmd &`), as the child process inherits the tool's stdout/stderr pipes and causes Vibe to hang indefinitely waiting for EOF. Always launch long-running processes fully detached with stdin/stdout/stderr redirected:
        ```bash
        setsid -f bash -c '<command> </dev/null >/tmp/<daemon>.log 2>&1'
        ```
      - **Stopping processes safely**: Never run `pkill -f "<pattern>"` or `pgrep -f "<pattern>"` with a literal string in the same subshell command (e.g. `pkill -f "uvicorn app.main" && ...`), because it matches the shell's own command line and kills the subshell itself (exit 144). Always use a bracketed character class (e.g. `pkill -f "[u]vicorn app.main"`) or resolve the PID in a separate step.
    '' + "\n" + import ./agent-commit-policy.nix git;
  };
  programs.mistral-vibe = {
    enable = true;
    package = pkgs.mistral-vibe.overridePythonAttrs (old: {
      doCheck = false;
      # Avoid blocking on non-TTY stdin (e.g. open socket in Claude Code Bash tool)
      # when a prompt is already provided via -p/--prompt or positional argument.
      postPatch = (old.postPatch or "") + ''
        substituteInPlace vibe/cli/cli.py \
          --replace-fail \
            "stdin_prompt = get_prompt_from_stdin()" \
            "stdin_prompt = None if (args.prompt or args.initial_prompt) else get_prompt_from_stdin()"

        substituteInPlace vibe/app_server/_turns.py \
          --replace-fail \
            '        self._queue_tasks: set[asyncio.Task[None]] = set()' \
            '        self._queue_tasks: set[asyncio.Task[None]] = set()
        self._write_vibe_session_state("idle", init=True)' \
          --replace-fail \
            '        if self._active_turn is None and status != "idle":' \
            '        self._write_vibe_session_state(status)
        if self._active_turn is None and status != "idle":'

        cat >> vibe/app_server/_turns.py << 'EOF'

def _turn_controller_write_vibe_session_state(self, status: str, *, init: bool = False) -> None:
    try:
        import atexit as _atexit, json as _json, os as _os, subprocess as _sp, time as _time
        from pathlib import Path as _Path
        _sdir = _Path(_os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "vibe-sessions"
        _sdir.mkdir(parents=True, exist_ok=True)
        _sfile = _sdir / f"{_os.getpid()}.json"
        if init:
            _atexit.register(lambda p=_sfile: p.unlink(missing_ok=True))
        _st = "working" if status == "running" else ("waiting" if status == "blocked" else "idle")
        _detail = (
            "Running turn" if _st == "working"
            else ("Waiting for approval" if _st == "waiting" else ("Session started" if init else "Idle (turn complete)"))
        )
        _cwd = str(self._agent_loop.cwd)
        _tmux_env = _os.environ.get("TMUX", "")
        _tmux_sock = _tmux_env.split(",", 1)[0] if _tmux_env else ""
        _tmux_pane = _os.environ.get("TMUX_PANE", "")
        _tmux_target = getattr(self, "_vibe_tmux_target", "")
        if init and _tmux_sock and _tmux_pane and not _tmux_target:
            try:
                _tmux_target = _sp.check_output(
                    ["tmux", "-S", _tmux_sock, "display-message", "-p", "-t", _tmux_pane, "#{session_name}:#{window_index}.#{pane_index}"],
                    stderr=_sp.DEVNULL, text=True, timeout=1
                ).strip()
            except Exception:
                _tmux_target = ""
            self._vibe_tmux_target = _tmux_target
        _tmp = _sdir / f".{_os.getpid()}.json.tmp"
        _tmp.write_text(_json.dumps({
            "agent": "vibe",
            "session_id": str(self._agent_loop.session_id),
            "pid": _os.getpid(),
            "state": _st,
            "detail": _detail,
            "updated_at": int(_time.time()),
            "cwd": _cwd,
            "project": _Path(_cwd).name or "unknown",
            "tmux_socket": _tmux_sock,
            "tmux_pane": _tmux_pane,
            "tmux_target": _tmux_target,
            "nvim_socket": _os.environ.get("NVIM", ""),
        }))
        _tmp.replace(_sfile)
    except Exception:
        pass

TurnController._write_vibe_session_state = _turn_controller_write_vibe_session_state  # type: ignore[attr-defined]
EOF
      '';
    });
    # Custom settings can be added here, e.g.:
    # settings = {
    #   theme = "auto";
    # };
  };
}
