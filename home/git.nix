{ ... }:
{
  programs.git = {
    enable = true;
    userName  = "Egor Pustovoytenko";
    userEmail = "puseg2006@gmail.com";

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
    };

    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      lg = "log --oneline --graph --decorate --all";
    };
  };
}
