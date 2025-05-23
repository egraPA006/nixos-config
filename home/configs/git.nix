{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    package = pkgs.git;

    # User info (change these)
    userName = "Egor Pustovoytenko";
    userEmail = "puseg2006@gmail.com";

    # Core settings
    extraConfig = {
      core = {
        editor = lib.mkDefault "vim";  # Change to your preferred editor
        pager = "less -FRX";
        autocrlf = "input";
      };
      color = {
        ui = "auto";
        diff = "auto";
        status = "auto";
      };
      pull = {
        rebase = true;
      };
      init = {
        defaultBranch = "main";
      };
    };

    # Minimal ignores
    ignores = [
      "*~"
      "*.swp"
      ".DS_Store"
      "*.pyc"
      "__pycache__"
      "node_modules/"
      "result"
    ];
  };
}