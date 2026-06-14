{ ... }:
{
  programs.git = {
    enable = true;

    settings = {
      user.name  = "Egor Pustovoytenko";
      user.email = "puseg2006@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        lg = "log --oneline --graph --decorate --all";
      };
    };
  };
}
