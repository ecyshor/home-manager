### Home manager using flakes

https://nix-community.github.io/home-manager/index.xhtml#sec-flakes-standalone

#### Shell

Find the shell path eg: `which fish`
Add it to `/etc/shells`
Change to the new shell `chsh`

#### Manual configs

##### Mullvadvpn

```
    # https://github.com/NixOS/nixpkgs/issues/121694#issuecomment-2159420924
    "/etc/sysctl.d/60-apparmor-namespace.conf".text = ''
      kernel.apparmor_restrict_unprivileged_userns=0
    '';
```