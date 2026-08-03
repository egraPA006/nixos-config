{ config, lib, pkgs, ... }:

let
  configDir = config.pino.configDir;
  vaultRoot = config.pino.bootstrap.vaultRoot;
in
{
  pino.subcommands.bootstrap = {
    description = "Provision a staged machine from the local vault";
    commands.server = {
      description = "Check or provision a remote NixOS server";
      commands = {
        check = { description = "Check a host's required files in the local vault"; usage = "<host>"; };
        apply = { description = "Perform the one-time initial server bootstrap"; usage = "<host> <address>"; };
        sync = { description = "Synchronize changed server secrets later"; usage = "<host> <address>"; };
      };
      helpText = ''
        The source is ${vaultRoot}/<host>/ and mirrors the remote
        /var/lib/pino/secrets/ tree. apply asks for the one-time code printed by
        scripts/server-stage.sh; sync works only after a successful apply.
      '';
      script = ''
        operation="''${1:-}"
        host="''${2:-}"
        address="''${3:-}"
        [ -n "$host" ] || { echo "A host name is required." >&2; exit 1; }
        flake=${lib.escapeShellArg configDir}
        source_root=${lib.escapeShellArg vaultRoot}/"$host"
        attr="path:$flake#nixosConfigurations.$host.config.pino.bootstrap.secrets"
        user_attr="path:$flake#nixosConfigurations.$host.config.pino.user.name"

        manifest="$(${pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' eval --json "$attr")" || {
          echo "Cannot evaluate bootstrap manifest for $host." >&2
          exit 1
        }
        mapfile -t sources < <(${pkgs.jq}/bin/jq -r 'to_entries[] | .value.source' <<< "$manifest")
        if [ "''${#sources[@]}" -eq 0 ]; then
          echo "No bootstrap secrets are declared for $host." >&2
          exit 1
        fi

        missing=0
        echo "Bootstrap manifest for $host:"
        while IFS=$'\t' read -r name source target; do
          if sudo ${pkgs.coreutils}/bin/test -f "$source_root/$source"; then
            printf '  OK       %-40s -> %s\n' "$source" "$target"
          else
            printf '  MISSING  %-40s -> %s\n' "$source" "$target"
            missing=1
          fi
        done < <(${pkgs.jq}/bin/jq -r 'to_entries[] | [.key, .value.source, .value.target] | @tsv' <<< "$manifest")
        [ "$missing" -eq 0 ] || exit 1
        [ "$operation" != check ] || exit 0

        [ -n "$address" ] || { echo "A server address is required." >&2; exit 1; }
        remote_user="$(${pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' eval --raw "$user_attr")"
        remote="$remote_user@$address"
        known_hosts="$(${pkgs.coreutils}/bin/mktemp)"
        cleanup() { ${pkgs.coreutils}/bin/rm -f "$known_hosts"; }
        trap cleanup EXIT INT TERM
        ${pkgs.openssh}/bin/ssh-keyscan -T 10 -t ed25519 "$address" > "$known_hosts" 2>/dev/null || {
          echo "Could not obtain the SSH host key from $address." >&2
          exit 1
        }
        fingerprint="$(${pkgs.openssh}/bin/ssh-keygen -lf "$known_hosts" -E sha256 | ${pkgs.gawk}/bin/awk '{print $2}')"
        echo "Remote ED25519 fingerprint: $fingerprint"
        read -r -p "Type the fingerprint shown by the server console: " expected
        [ "$expected" = "$fingerprint" ] || { echo "Fingerprint mismatch." >&2; exit 1; }

        ssh_options=(-o "UserKnownHostsFile=$known_hosts" -o StrictHostKeyChecking=yes)
        remote_host="$(${pkgs.openssh}/bin/ssh "''${ssh_options[@]}" "$remote" hostname)"
        [ "$remote_host" = "$host" ] || {
          echo "Remote hostname is '$remote_host', expected '$host'." >&2
          exit 1
        }

        receiver_operation=sync
        receiver_args=(sync)
        if [ "$operation" = apply ]; then
          read -r -p "One-time bootstrap code: " code
          [ -n "$code" ] || { echo "A bootstrap code is required." >&2; exit 1; }
          receiver_operation=apply
          receiver_args=(apply "$code")
        fi
        echo "Sending ''${#sources[@]} root-only file(s) to $host..."
        printf -v remote_command '%q ' sudo pino-bootstrap-receive "''${receiver_args[@]}"
        # The command is deliberately shell-escaped above before SSH receives it.
        # shellcheck disable=SC2029
        sudo ${pkgs.gnutar}/bin/tar -C "$source_root" -cf - -- "''${sources[@]}" \
          | ${pkgs.openssh}/bin/ssh "''${ssh_options[@]}" "$remote" \
              "$remote_command"
        echo "Server secret $receiver_operation completed for $host."
      '';
    };
  };
}
