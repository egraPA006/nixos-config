{ pkgs, ... }:
{
  programs.bash = {
    enable = true;
    enableCompletion = true;

    shellAliases = {
      ll  = "ls -la";
      la  = "ls -A";
      ".." = "cd ..";
      "..." = "cd ../..";
    };

    # ble.sh: syntax highlighting + better line editing for bash
    initExtra = ''
      source ${pkgs.blesh}/share/blesh/ble.sh --noattach
      [[ ! ''${BLE_VERSION-} ]] || ble-attach
    '';
  };
}
