{ pkgs, ... }:
let
  configDir = "/home/egrapa/nixos-config";
in
{
  programs.fish.enable = true;

  pino.subcommands = {
    rebuild = {
      description = "Apply config changes";
      script = "sudo nixos-rebuild switch --flake ${configDir}#$(hostname)";
    };
    rollback = {
      description = "Roll back to previous NixOS generation";
      script = "sudo nixos-rebuild switch --rollback";
    };
    gc = {
      description = "Garbage-collect old Nix generations";
      script = ''
        sudo nix-collect-garbage --delete-older-than 14d
        nix-collect-garbage --delete-older-than 14d
        sudo nixos-rebuild boot --flake ${configDir}#$(hostname)
      '';
    };
    update = {
      description = "Update flake inputs, snapshot, rebuild";
      script = builtins.readFile ../../scripts/pino-update.sh;
    };
    snap = {
      description = "Manage btrfs snapshots  (snap help for details)";
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
