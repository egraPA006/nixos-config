{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.meld ];

  pino.subcommands.files = {
    description = "Compare and manually merge two folders";
    commands.merge = {
      description = "Open a two-way folder comparison in Meld";
      usage = "<other-folder> [local-folder]";
    };
    helpText = ''
      The local folder defaults to the current directory. Meld only applies
      copies and deletions that you choose in its interface; Pino keeps no
      snapshots, datasets, or synchronization state.
    '';
    script = ''
      [ "''${1:-}" = merge ] || { echo "Run 'pino files help' for usage." >&2; exit 1; }
      other="''${2:-}"
      local_folder="''${3:-.}"
      [ "$#" -le 3 ] && [ -n "$other" ] || {
        echo "Usage: pino files merge <other-folder> [local-folder]" >&2
        exit 1
      }
      [ -d "$local_folder" ] || { echo "Local folder does not exist: $local_folder" >&2; exit 1; }
      [ -d "$other" ] || { echo "Other folder does not exist: $other" >&2; exit 1; }
      exec ${pkgs.meld}/bin/meld "$local_folder" "$other"
    '';
  };
}
