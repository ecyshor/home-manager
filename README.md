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
