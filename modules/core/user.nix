{ config, ... }:

let
  user = config.pino.user;
in
{
  home-manager.users.${user.name} = {
    home.username = user.name;
    home.homeDirectory = user.home;
    home.stateVersion = "25.05";
    programs.home-manager.enable = true;

    programs.bash = {
      enable = true;
      enableCompletion = true;

      shellAliases = {
        ll  = "ls -la";
        la  = "ls -A";
        ".." = "cd ..";
        "..." = "cd ../..";
      };
    };

    programs.fish = {
      enable = true;
      shellAliases = {
        ll  = "ls -la";
        la  = "ls -A";
        ".." = "cd ..";
        "..." = "cd ../..";
      };
    };
  };
}
