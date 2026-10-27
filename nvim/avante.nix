{ pkgs, ... }: {

  home.packages = [ pkgs.claude-agent-acp ];

  programs.nixvim.plugins.avante = {
    enable = true;

    settings = {
      # Claude Code is the active ACP provider (handles planning & review, and
      # delegates basic implementation to Mistral Vibe). Switch between
      # "claude-code" and "mistral-vibe" anytime with :AvanteSwitchProvider.
      provider = "claude-code";

      # Agent Client Protocol providers; the agent runs as a subprocess of
      # Neovim. Avante spawns ACP agents with a minimal environment (PATH
      # plus the env below), so pass through HOME (to locate ~/.claude and
      # ~/.vibe) and the D-Bus session vars to reach the OS keyring where
      # credentials are stored after browser sign-in.
      acp_providers = {
        "claude-code" = {
          command = "claude-agent-acp";
          args = [ ];
          env.__raw = ''
            (function()
              local env = {
                NODE_NO_WARNINGS = "1",
                ACP_PERMISSION_MODE = "bypassPermissions",
              }
              for _, name in ipairs({
                "HOME",
                "DBUS_SESSION_BUS_ADDRESS",
                "XDG_RUNTIME_DIR",
                "ANTHROPIC_API_KEY",
                "ANTHROPIC_BASE_URL",
              }) do
                local value = os.getenv(name)
                if value then env[name] = value end
              end
              return env
            end)()
          '';
        };

        "mistral-vibe" = {
          command = "vibe-acp";
          args = [ ];
          env.__raw = ''
            (function()
              local env = {}
              for _, name in ipairs({ "HOME", "DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR" }) do
                local value = os.getenv(name)
                if value then env[name] = value end
              end
              return env
            end)()
          '';
        };
      };

      # Use telescope for avante's pickers (provider/model/session selection).
      selector.provider = "telescope";
    };
  };
}
