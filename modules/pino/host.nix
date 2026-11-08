{ pkgs, ... }:
{
  pino.subcommands.host = {
    description = "Run Pino on a server using its SSH alias";
    usage = "<mosk|halos> <pino-command ...>";
    helpText = ''
      Examples: pino host mosk server status
                pino host mosk server vpn mode set private
                pino host mosk server xray status
                pino host mosk os rebuild
      Uses your configured SSH identity and normal host-key verification.
      Secrets belong in Bitwarden, not command arguments.
    '';
    script = ''
      host="''${1:-}"
      case "$host" in mosk|halos) ;; *) echo "Host must be mosk or halos" >&2; exit 1 ;; esac
      shift
      [ "$#" -gt 0 ] || { echo "Specify a Pino command" >&2; exit 1; }
      remote=/run/current-system/sw/bin/pino
      for arg in "$@"; do
        [[ "$arg" =~ ^[A-Za-z0-9_./:@=-]+$ ]] || { echo "Unsupported remote argument" >&2; exit 1; }
        remote+=" $arg"
      done
      tty=()
      if [ -t 0 ] && [ -t 1 ]; then tty=(-t); fi
      exec ${pkgs.openssh}/bin/ssh "''${tty[@]}" "$host" "$remote"
    '';
  };
}
