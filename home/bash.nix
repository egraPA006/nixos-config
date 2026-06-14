{ ... }:
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
}
