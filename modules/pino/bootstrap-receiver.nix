{ config, lib, pkgs, ... }:

let
  cfg = config.pino.secrets;
  user = config.pino.user.name;
  secrets = cfg.entries;
  manifest = pkgs.writeText "pino-bootstrap-manifest.tsv" (
    lib.concatMapStringsSep "\n" (name:
      let secret = secrets.${name};
      in lib.concatStringsSep "\t" [
        secret.source
        (if secret.recursive then "1" else "0")
      ]) (builtins.attrNames secrets) + "\n"
  );
  receiver = pkgs.writeShellApplication {
    name = "pino-bootstrap-receive";
    runtimeInputs = with pkgs; [ coreutils findutils gawk gnugrep gnutar rsync systemd ];
    text = ''
      set -euo pipefail

      operation="''${1:-}"
      code="''${2:-}"
      state_dir=/var/lib/pino/bootstrap
      pending="$state_dir/pending"
      complete="$state_dir/complete"
      manifest=${manifest}

      case "$operation" in
        apply)
          [ -f "$pending" ] || { echo "Initial bootstrap is not pending." >&2; exit 1; }
          read -r expected_code expires < "$pending"
          [ "$code" = "$expected_code" ] || { echo "Invalid bootstrap code." >&2; exit 1; }
          now="$(${pkgs.coreutils}/bin/date +%s)"
          [ "$now" -le "$expires" ] || { echo "Bootstrap code has expired." >&2; exit 1; }
          ;;
        sync)
          [ -f "$complete" ] || { echo "Initial bootstrap has not completed." >&2; exit 1; }
          ;;
        *) echo "Usage: pino-bootstrap-receive <apply CODE|sync>" >&2; exit 1 ;;
      esac

      staging="$(${pkgs.coreutils}/bin/mktemp -d /run/pino-bootstrap.XXXXXX)"
      incoming=""
      cleanup() { ${pkgs.coreutils}/bin/rm -rf "$staging" "''${incoming:-}"; }
      trap cleanup EXIT INT TERM
      ${pkgs.gnutar}/bin/tar --extract --file=- --directory="$staging" \
        --no-same-owner --no-same-permissions

      if ${pkgs.findutils}/bin/find "$staging" -type l -o -type b -o -type c -o -type p -o -type s \
        | ${pkgs.gnugrep}/bin/grep -q .; then
        echo "Bootstrap archive contains an unsupported file type." >&2
        exit 1
      fi

      while IFS= read -r file; do
        relative="''${file#"$staging"/}"
        if ! ${pkgs.gawk}/bin/awk -F '\t' -v file="$relative" '
          ($2 == "0" && file == $1) || ($2 == "1" && index(file, $1 "/") == 1) { found=1 }
          END { exit !found }
        ' "$manifest"; then
          echo "Unexpected bootstrap file: $relative" >&2
          exit 1
        fi
      done < <(${pkgs.findutils}/bin/find "$staging" -type f)

      cache=${lib.escapeShellArg cfg.provisionedDir}
      incoming="$(${pkgs.coreutils}/bin/mktemp -d /run/pino-secrets-incoming.XXXXXX)"
      while IFS=$'\t' read -r source recursive; do
        [ -n "$source" ] || continue
        if [ "$recursive" = 1 ]; then
          [ -d "$staging/$source" ] || { echo "Required bootstrap directory is missing: $source" >&2; exit 1; }
          ${pkgs.coreutils}/bin/mkdir -p "$incoming/$source"
          ${pkgs.rsync}/bin/rsync -a "$staging/$source/" "$incoming/$source/"
        else
          [ -f "$staging/$source" ] || { echo "Required bootstrap file is missing: $source" >&2; exit 1; }
          ${pkgs.coreutils}/bin/install -D -m 0600 "$staging/$source" "$incoming/$source"
        fi
      done < "$manifest"

      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root "$cache"
      ${pkgs.rsync}/bin/rsync -a --delete "$incoming/" "$cache/"
      ${pkgs.findutils}/bin/find "$cache" -type d -exec ${pkgs.coreutils}/bin/chown root:root {} + -exec ${pkgs.coreutils}/bin/chmod 0700 {} +
      ${pkgs.findutils}/bin/find "$cache" -type f -exec ${pkgs.coreutils}/bin/chown root:root {} + -exec ${pkgs.coreutils}/bin/chmod 0600 {} +
      ${pkgs.coreutils}/bin/rm -rf "$incoming"
      /run/current-system/sw/bin/pino-secrets-deploy --restart
      if [ "$operation" = apply ]; then
        ${pkgs.coreutils}/bin/rm -f "$pending"
        ${pkgs.coreutils}/bin/touch "$complete"
        ${pkgs.coreutils}/bin/chmod 0600 "$complete"
      fi
      echo "Installed ''$(wc -l < "$manifest") declared secret projection(s) for ${config.networking.hostName}."
    '';
  };
in
{
  assertions = lib.concatMap (name:
    let secret = secrets.${name};
    in [
      {
        assertion = secret.source != "" && !(lib.hasPrefix "/" secret.source)
          && !(lib.hasInfix ".." secret.source) && !(lib.hasInfix "\n" secret.source);
        message = "pino.secrets.entries.${name}.source must be a safe relative path";
      }
    ]) (builtins.attrNames secrets);

  environment.systemPackages = [ receiver ];

  # Bootstrap is reachable only with a key installed by the staging script.
  # The one-time code is an additional authorization factor for the first
  # projection, not an SSH replacement.
  services.openssh = {
    enable = lib.mkDefault true;
    openFirewall = lib.mkDefault true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AuthorizedKeysFile = ".ssh/authorized_keys /etc/ssh/authorized_keys.d/%u";
    };
  };
  systemd.tmpfiles.rules = [
    "d /etc/ssh/authorized_keys.d 0755 root root -"
    "d /var/lib/pino/bootstrap 0700 root root -"
  ];

  pino.subcommands.bootstrap.commands.receiver = {
    description = "Inspect or renew the initial bootstrap code";
    commands = {
      status.description = "Show whether initial bootstrap is pending or complete";
      code.description = "Display the current unexpired bootstrap code";
      renew.description = "Issue a replacement code valid for one hour";
    };
    helpText = ''
      Run these commands as root from the trusted server console. A successful
      initial bootstrap consumes the code permanently; later changes use
      `pino bootstrap host sync` from a trusted vault machine.
    '';
    script = ''
      [ "$(${pkgs.coreutils}/bin/id -u)" -eq 0 ] || {
        echo "Run this command as root from the trusted server console." >&2
        exit 1
      }

      operation="''${1:-}"
      state_dir=/var/lib/pino/bootstrap
      pending="$state_dir/pending"
      complete="$state_dir/complete"

      read_pending() {
        [ -f "$pending" ] || return 1
        read -r code expires < "$pending"
        [[ "$code" =~ ^[0-9a-f]{12}$ && "$expires" =~ ^[0-9]+$ ]] || {
          echo "The pending bootstrap state is malformed." >&2
          exit 1
        }
      }

      case "$operation" in
        status)
          if [ -f "$complete" ]; then
            echo "Initial bootstrap: complete"
          elif ! read_pending; then
            echo "Initial bootstrap: not pending"
          elif [ "$(${pkgs.coreutils}/bin/date +%s)" -le "$expires" ]; then
            echo "Initial bootstrap: pending"
            echo "Expires: $(${pkgs.coreutils}/bin/date --date="@$expires" --iso-8601=seconds)"
          else
            echo "Initial bootstrap: expired"
          fi
          ;;
        code)
          [ ! -f "$complete" ] || {
            echo "Initial bootstrap is already complete; use server secret sync for later changes." >&2
            exit 1
          }
          read_pending || {
            echo "No bootstrap code is pending. Run: pino bootstrap receiver renew" >&2
            exit 1
          }
          [ "$(${pkgs.coreutils}/bin/date +%s)" -le "$expires" ] || {
            echo "The bootstrap code has expired. Run: pino bootstrap receiver renew" >&2
            exit 1
          }
          echo "Bootstrap code: $code"
          echo "Expires: $(${pkgs.coreutils}/bin/date --date="@$expires" --iso-8601=seconds)"
          ;;
        renew)
          [ ! -f "$complete" ] || {
            echo "Initial bootstrap is already complete; refusing to reopen it." >&2
            exit 1
          }
          ${pkgs.coreutils}/bin/install -d -m 0700 "$state_dir"
          code="$(${pkgs.coreutils}/bin/od -An -N6 -tx1 /dev/urandom | ${pkgs.coreutils}/bin/tr -d ' \n')"
          expires="$(( $(${pkgs.coreutils}/bin/date +%s) + 3600 ))"
          replacement="$(${pkgs.coreutils}/bin/mktemp "$state_dir/pending.XXXXXX")"
          cleanup() { ${pkgs.coreutils}/bin/rm -f "$replacement"; }
          trap cleanup EXIT INT TERM
          ${pkgs.coreutils}/bin/printf '%s %s\n' "$code" "$expires" > "$replacement"
          ${pkgs.coreutils}/bin/chmod 0600 "$replacement"
          ${pkgs.coreutils}/bin/mv -f "$replacement" "$pending"
          trap - EXIT INT TERM
          echo "Bootstrap code: $code"
          echo "Expires: $(${pkgs.coreutils}/bin/date --date="@$expires" --iso-8601=seconds)"
          ;;
        *) echo "Run 'pino bootstrap receiver help' for usage." >&2; exit 1 ;;
      esac
    '';
  };

  security.sudo.extraRules = [{
    users = [ user ];
    commands = [{
      command = "/run/current-system/sw/bin/pino-bootstrap-receive";
      options = [ "NOPASSWD" ];
    }];
  }];

  systemd.services.pino-bootstrap-expire = {
    description = "Expire an unused Pino initial-bootstrap code";
    serviceConfig.Type = "oneshot";
    script = ''
      pending=/var/lib/pino/bootstrap/pending
      [ -f "$pending" ] || exit 0
      read -r _ expires < "$pending"
      [ "$(${pkgs.coreutils}/bin/date +%s)" -le "$expires" ] || ${pkgs.coreutils}/bin/rm -f "$pending"
    '';
  };
  systemd.timers.pino-bootstrap-expire = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
}
