{ ... }:
{
  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.configurationLimit = 5;

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "egrapa" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}
