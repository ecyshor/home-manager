{ pkgs, ... }: {
  home.file.".vibe/config.toml".force = true;
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
            '        if self._active_turn is None and status != "idle":' \
            '        try:
            import json as _json, os as _os, time as _time
            from pathlib import Path as _Path
            _sdir = _Path(_os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "vibe-sessions"
            _sdir.mkdir(parents=True, exist_ok=True)
            _st = "working" if status == "running" else ("waiting" if status == "blocked" else "idle")
            (_sdir / f"{_os.getpid()}.json").write_text(_json.dumps({
                "session_id": self._agent_loop.session_id,
                "pid": _os.getpid(),
                "state": _st,
                "updated_at": int(_time.time()),
                "cwd": str(self._agent_loop.cwd),
            }))
        except Exception:
            pass
        if self._active_turn is None and status != "idle":'
      '';
    });
    # Custom settings can be added here, e.g.:
    # settings = {
    #   theme = "auto";
    # };
  };
}
