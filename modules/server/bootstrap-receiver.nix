{ config, lib, pkgs, ... }:

let
  cfg = config.pino.bootstrap;
  user = config.pino.user.name;
  secrets = cfg.secrets;
  manifest = pkgs.writeText "pino-bootstrap-manifest.tsv" (
    lib.concatMapStringsSep "\n" (name:
      let secret = secrets.${name};
      in lib.concatStringsSep "\t" [
        secret.source
        secret.target
        secret.owner
        secret.group
        secret.mode
        (lib.concatStringsSep "," secret.restartUnits)
      ]) (builtins.attrNames secrets) + "\n"
  );
  receiver = pkgs.writeShellApplication {
    name = "pino-bootstrap-receive";
    runtimeInputs = with pkgs; [ coreutils findutils gnugrep gnutar systemd ];
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
      cleanup() { ${pkgs.coreutils}/bin/rm -rf "$staging"; }
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
        if ! ${pkgs.gawk}/bin/awk -F '\t' -v source="$relative" '$1 == source { found=1 } END { exit !found }' "$manifest"; then
          echo "Unexpected bootstrap file: $relative" >&2
          exit 1
        fi
      done < <(${pkgs.findutils}/bin/find "$staging" -type f)

      units=()
      while IFS=$'\t' read -r source target owner group mode restart_csv; do
        [ -n "$source" ] || continue
        source_file="$staging/$source"
        [ -f "$source_file" ] || { echo "Required bootstrap file is missing: $source" >&2; exit 1; }
        case "$target" in
          /var/lib/pino/secrets/*) ;;
          *) echo "Refusing destination outside /var/lib/pino/secrets: $target" >&2; exit 1 ;;
        esac
        ${pkgs.coreutils}/bin/install -D -o "$owner" -g "$group" -m "$mode" "$source_file" "$target"
        if [ -n "$restart_csv" ]; then
          IFS=',' read -r -a current_units <<< "$restart_csv"
          units+=("''${current_units[@]}")
        fi
      done < "$manifest"

      if [ "''${#units[@]}" -gt 0 ]; then
        mapfile -t units < <(${pkgs.coreutils}/bin/printf '%s\n' "''${units[@]}" | ${pkgs.coreutils}/bin/sort -u)
        for unit in "''${units[@]}"; do
          ${pkgs.systemd}/bin/systemctl restart "$unit"
        done
      fi
      if [ "$operation" = apply ]; then
        ${pkgs.coreutils}/bin/rm -f "$pending"
        ${pkgs.coreutils}/bin/touch "$complete"
        ${pkgs.coreutils}/bin/chmod 0600 "$complete"
      fi
      echo "Installed ''$(wc -l < "$manifest") manifest secret(s) for ${config.networking.hostName}."
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
        message = "pino.bootstrap.secrets.${name}.source must be a safe relative path";
      }
      {
        assertion = lib.hasPrefix "/var/lib/pino/secrets/" secret.target;
        message = "pino.bootstrap.secrets.${name}.target must be under /var/lib/pino/secrets";
      }
    ]) (builtins.attrNames secrets);

  environment.systemPackages = [ receiver ];

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
