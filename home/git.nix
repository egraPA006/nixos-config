{ ... }:
{
  programs.git = {
    enable = true;

    settings = {
      user.name = "Egor Pustovoytenko";
      user.email = "puseg2006@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = false;
      core.editor = "vim";
    };
  };
}
