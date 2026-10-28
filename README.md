### Home manager using flakes

https://nix-community.github.io/home-manager/index.xhtml#sec-flakes-standalone

#### Shell

Find the shell path eg: `which fish`
Add it to `/etc/shells`
Change to the new shell `chsh`

#### Manual configs

Vitals require installing `apt install gir1.2-gtop-2.0`

##### autocpu freq

/etc/systemd/system/auto-cpufreq.service

```
[Unit]
Description=auto-cpufreq - Automatic CPU speed & power optimizer
After=network.target

[Service]
Type=simple
# This automatically finds the current nix-store path for the binary
ExecStart=/home/nicu/.nix-profile/bin/auto-cpufreq --daemon --config /home/nicu/.config/auto-cpufreq/auto-cpufreq.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

mask

`sudo systemctl mask power-profiles-daemon.service`


##### Mullvadvpn

```
    # https://github.com/NixOS/nixpkgs/issues/121694#issuecomment-2159420924
    "/etc/sysctl.d/60-apparmor-namespace.conf".text = ''
      kernel.apparmor_restrict_unprivileged_userns=0
    '';
```

#### AI Agent Sleep Inhibitor (Managed by Home Manager)

Configured fully through Home Manager in `agent-sleep-inhibitor.nix`, `claude-code.nix`, and `mistral-vibe.nix` (no manual system configuration required):

- **Behavior**: Prevents idle/automatic sleep whenever any Claude Code (`claude`) or Mistral Vibe (`vibe` / `vibe-acp`) agent is actively working (`state == "working"` or running with `-p`), unless battery level is under **30%**. Closing the laptop lid still suspends/hibernates normally via `systemd-logind`.
- **Service**: Runs as the systemd user unit `agent-sleep-inhibitor.service`, started automatically with the session.
- **Verification commands**:
  - Check service status: `systemctl --user status agent-sleep-inhibitor.service`
  - List active GNOME session inhibitors: `gnome-session-inhibit -l`
  - List active systemd logind inhibitors: `systemd-inhibit --list`
