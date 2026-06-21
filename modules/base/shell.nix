{ pkgs, ... }:
let
  configDir = "/home/egrapa/nixos-config";
in
{
  programs.fish.enable = true;

  pino.subcommands = {
    rebuild = {
      description = "Apply config changes";
      helpText = ''
        pino rebuild — apply NixOS config changes
          Runs: sudo nixos-rebuild switch --flake ${configDir}#<hostname>
      '';
      script = ''sudo nixos-rebuild switch --flake "${configDir}#$(hostname)"'';
    };

    rollback = {
      description = "Roll back to previous NixOS generation";
      helpText = ''
        pino rollback — roll back to the previous NixOS generation
          Runs: sudo nixos-rebuild switch --rollback
          Tip: pick a specific generation at boot from the systemd-boot menu.
      '';
      script = "sudo nixos-rebuild switch --rollback";
    };

    gc = {
      description = "Garbage-collect old Nix generations";
      helpText = ''
        pino gc — garbage-collect Nix generations older than 14 days
          Cleans system + user profiles, then runs nixos-rebuild boot
          to remove old entries from the boot menu.
      '';
      script = ''
        sudo nix-collect-garbage --delete-older-than 14d
        nix-collect-garbage --delete-older-than 14d
        sudo nixos-rebuild boot --flake "${configDir}#$(hostname)"
      '';
    };

    update = {
      description = "Update flake inputs, snapshot, rebuild";
      helpText = ''
        pino update — update flake inputs and rebuild
          1. Removes old pre-update snapshots of root + home
          2. Creates fresh pre-update snapshots
          3. Runs: nix flake update
          4. Runs: nixos-rebuild switch
      '';
      script = builtins.readFile ../../scripts/pino-update.sh;
    };

    snap = {
      description = "Manage btrfs snapshots";
      helpText = ''
        pino snap — btrfs snapshot management (root + home)
          pino snap <label>          Create snapshot of root + home
          pino snap ls               List snapshots
          pino snap rb <N>           Roll back root + home to snapshot N
          pino snap rm <N>           Delete snapshot N
          pino snap data <...>       Data disk snapshots  (pino snap data help)
      '';
      script = builtins.readFile ../../scripts/pino-snap.sh;
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    rsync
    file
    unzip
  ];
}
