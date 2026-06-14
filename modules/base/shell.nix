{ pkgs, config, ... }:
{
  programs.fish.enable = true;
  programs.fish.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake /home/egrapa/nixos-config#${config.networking.hostName}";
    update = "sudo snapper -c root create -d 'pre-update' && sudo snapper -c home create -d 'pre-update' && nix flake update /home/egrapa/nixos-config && sudo nixos-rebuild switch --flake /home/egrapa/nixos-config#${config.networking.hostName}";
    snap = "sudo snapper -c root create -d $argv[1] && sudo snapper -c home create -d $argv[1]";
    snapls = "echo '=== root ===' && sudo snapper -c root list && echo '=== home ===' && sudo snapper -c home list";
    snaprb = "sudo snapper -c root undochange $argv[1]..0 && sudo snapper -c home undochange $argv[1]..0";
    snaprm = "sudo snapper -c root delete $argv[1] && sudo snapper -c home delete $argv[1]";
    # data disks — independent from system
    dsnap = "sudo snapper -c fast create -d $argv[1] && sudo snapper -c slow create -d $argv[1]";
    dsnapls = "echo '=== fast ===' && sudo snapper -c fast list && echo '=== slow ===' && sudo snapper -c slow list";
    dsnaprb-fast = "sudo snapper -c fast undochange $argv[1]..0";
    dsnaprb-slow = "sudo snapper -c slow undochange $argv[1]..0";
    dsnaprm = "sudo snapper -c fast delete $argv[1] && sudo snapper -c slow delete $argv[1]";
  };

  programs.fish.functions.snapclean = {
    description = "Delete all pre-update snapshots except the most recent one";
    body = ''
      for cfg in root home
        set ids (sudo snapper -c $cfg list --columns number,description | string trim | awk '$2 == "pre-update" {print $1}' | head -n -1)
        if test (count $ids) -gt 0
          sudo snapper -c $cfg delete $ids
          echo "[$cfg] deleted snapshots: $ids"
        else
          echo "[$cfg] nothing to clean"
        end
      end
    '';
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
