# Proton Drive tooling: the official Proton Drive CLI plus an rclone FUSE
# mount of the Drive "Docs" folder at ~/ProtonDrive/Docs.
#
# Setup: run `pass-cli login` once, then `home-manager switch`. The rclone
# remote credentials are fetched at runtime from Proton Pass by the
# rclone-proton-config helper (ExecStartPre of the mount service) and written
# to ~/.config/rclone/rclone.conf with mode 0600 — secrets never land in the
# nix store, in logs, or in process argv. After changing the Pass item,
# regenerate the config with `rclone-proton-config --force`.
#
# Note: rclone's protondrive backend moves deleted files/folders to the Drive
# trash instead of permanently deleting them; `rclone cleanup proton:` empties
# the trash. No permanent-delete flag is used anywhere here.
{ config, pkgs, protonPkgs, ... }:
let
  # Proton Pass vault "Family", login item "protonmail.com" (nicureut@pm.me).
  # Opaque item identifiers, not secrets: the item content is only decrypted
  # at runtime by pass-cli using the keyring session.
  passShareId = "TJ_sTYpCxs_9svQ9vau1NEaZKUO6lkR3OcuFT6Ckh3Dkm27IrrgS2uswkn2vlskx_h_vtQMiPzubbrMIqJANbw==";
  passItemId = "TytSUgpy28goUBNFfsm9Uo-qkSsbjAkcbQquvhroXt6YyXkmxpbMcWarFnJFnIliXfJKgVbG4buetuo64lPNhw==";
  remote = "proton";
  mountPoint = "${config.home.homeDirectory}/ProtonDrive/Docs";
  rcloneConf = "${config.xdg.configHome}/rclone/rclone.conf";

  # Fetch the Proton login item from Proton Pass and (re)write the [proton]
  # section of rclone.conf. Secret values stay in shell variables and stdin
  # pipes only — never in argv, files other than rclone.conf, or output.
  rclone-proton-config = pkgs.writeShellApplication {
    name = "rclone-proton-config";
    runtimeInputs = [
      pkgs.proton-pass-cli
      pkgs.rclone
      pkgs.jq
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      SHARE="${passShareId}"
      ITEM="${passItemId}"
      CONF="${rcloneConf}"

      usage() {
        echo "usage: rclone-proton-config [--force]"
      }

      force=0
      for arg in "$@"; do
        case "$arg" in
          --force) force=1 ;;
          -h | --help) usage; exit 0 ;;
          *)
            echo "rclone-proton-config: unknown argument '$arg'" >&2
            usage >&2
            exit 2
            ;;
        esac
      done

      # rclone writes its cached session tokens back into rclone.conf, so an
      # existing [proton] section means we are already authenticated;
      # regenerating on every start would force a fresh Proton login each time.
      if [ "$force" -eq 0 ] && [ -f "$CONF" ] && [ -n "$(sed -n 's/^\[proton\]$/found/p' "$CONF")" ]; then
        exit 0
      fi

      if ! item_json="$(pass-cli item view --share-id "$SHARE" --item-id "$ITEM" --output json)"; then
        echo "rclone-proton-config: 'pass-cli item view' failed (run 'pass-cli login' first?)" >&2
        exit 1
      fi
      if ! printf '%s' "$item_json" | jq -e . >/dev/null 2>&1; then
        echo "rclone-proton-config: pass-cli did not return valid JSON" >&2
        exit 1
      fi

      email="$(printf '%s' "$item_json" | jq -r '.item.content.content.Login.email // empty')"
      if [ -z "$email" ]; then
        email="$(printf '%s' "$item_json" | jq -r '.item.content.content.Login.username // empty')"
      fi
      password="$(printf '%s' "$item_json" | jq -r '.item.content.content.Login.password // empty')"
      totp_uri="$(printf '%s' "$item_json" | jq -r '.item.content.content.Login.totp_uri // empty')"

      if [ -z "$email" ] || [ -z "$password" ]; then
        echo "rclone-proton-config: Proton Pass item has no usable email/password" >&2
        exit 1
      fi

      otp_secret=""
      if [ -n "$totp_uri" ]; then
        case "$totp_uri" in
          otpauth://*)
            otp_secret="$(printf '%s' "$totp_uri" | sed -n 's/.*[?&]secret=\([^&]*\).*/\1/p')"
            ;;
          *)
            otp_secret="$totp_uri"
            ;;
        esac
      fi

      # Never put secrets in argv: rclone obscure reads the plaintext from stdin.
      obscured_password="$(printf '%s' "$password" | rclone obscure -)"
      obscured_otp=""
      if [ -n "$otp_secret" ]; then
        obscured_otp="$(printf '%s' "$otp_secret" | rclone obscure -)"
      fi

      # Atomic write: temp file in the same directory, then rename over the config.
      umask 077
      conf_dir="$(dirname "$CONF")"
      mkdir -p "$conf_dir"
      tmp="$(mktemp "$conf_dir/.rclone.conf.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT

      # Keep any other remotes; drop only the existing [proton] section.
      if [ -f "$CONF" ]; then
        sed '/^\[proton\]$/,/^\[/{ /^\[proton\]$/d; /^\[/!d; }' "$CONF" > "$tmp"
      else
        : > "$tmp"
      fi
      {
        printf '[proton]\n'
        printf 'type = protondrive\n'
        printf 'username = %s\n' "$email"
        printf 'password = %s\n' "$obscured_password"
        if [ -n "$obscured_otp" ]; then
          printf 'otp_secret_key = %s\n' "$obscured_otp"
        fi
      } >> "$tmp"

      chmod 600 "$tmp"
      mv "$tmp" "$CONF"
      echo "wrote [proton] remote to $CONF"
    '';
  };
in
{
  home.packages = [
    protonPkgs.proton-drive-cli
    pkgs.rclone
    rclone-proton-config
  ];

  systemd.user.services.rclone-proton-docs = {
    Unit = {
      Description = "rclone mount of Proton Drive Docs";
      # pass-cli keeps its session in the GNOME keyring; rclone needs the net.
      After = [
        "network-online.target"
        "gnome-keyring-daemon.service"
      ];
      Wants = [
        "network-online.target"
        "gnome-keyring-daemon.service"
      ];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "notify";
      # Restricted PATH so rclone finds the setuid system fusermount3
      # (/usr/bin/fusermount3) instead of a nix-store FUSE.
      Environment = "PATH=/usr/bin:/bin";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p ${mountPoint}"
        "${rclone-proton-config}/bin/rclone-proton-config"
      ];
      ExecStart = "${pkgs.rclone}/bin/rclone mount ${remote}:Docs ${mountPoint} --vfs-cache-mode full --vfs-cache-max-size 5G --vfs-cache-max-age 24h --dir-cache-time 5m --poll-interval 0 --vfs-write-back 10s --log-level INFO";
      ExecStop = "/usr/bin/fusermount3 -uz ${mountPoint}";
      Restart = "on-failure";
      RestartSec = 30;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
