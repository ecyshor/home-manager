{ ... }: {

  programs.nixvim.plugins.avante = {
    enable = true;

    settings = {
      # Mistral Vibe is the active provider (an ACP agent), so mode/model
      # pickers and the sidebar all drive vibe-acp instead of a plain LLM.
      provider = "mistral-vibe";

      # Agent Client Protocol providers; the agent runs as a subprocess of
      # Neovim. Avante spawns ACP agents with a minimal environment (PATH
      # plus the env below), so pass through what vibe-acp needs: HOME to
      # locate ~/.vibe, and the D-Bus session vars to reach the OS keyring
      # where the Mistral credential is stored after browser sign-in.
      acp_providers."mistral-vibe" = {
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

      # Use telescope for avante's pickers (provider/model/session selection).
      selector.provider = "telescope";
    };
  };
}
