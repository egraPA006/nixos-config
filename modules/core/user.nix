{ ... }:

{
  home-manager.users.egrapa = {
    home.username = "egrapa";
    home.homeDirectory = "/home/egrapa";
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
