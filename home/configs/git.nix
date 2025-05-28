{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Egor Pustovoytenko";
    userEmail = "puseg2006@gmail.com";
    extraConfig = {
      core = {
        # editor = "vim";  # Change to your preferred editor
        pager = "less -FRX";
        autocrlf = "input";
      };
      init = {
        defaultBranch = "main";
      };
    };
    ignores = [
      # "*~"
      # "*.swp"
      # ".DS_Store"
      # "*.pyc"
      ".vscode"
      "__pycache__"
      # "node_modules/"
      # "result"
    ];
  };

  # User info
  

  #   # # Core settings
  #   # extraConfig = {
  #   #   core = {
  #   #     editor = "vim";  # Change to your preferred editor
  #   #     pager = "less -FRX";
  #   #     autocrlf = "input";
  #   #   };
  #   #   color = {
  #   #     ui = "auto";
  #   #     diff = "auto";
  #   #     status = "auto";
  #   #   };
  #   #   pull = {
  #   #     rebase = true;
  #   #   };
  #   #   init = {
  #   #     defaultBranch = "main";
  #   #   };
  #   # };

  #   # # Minimal ignores
  #   # ignores = [
  #   #   "*~"
  #   #   "*.swp"
  #   #   ".DS_Store"
  #   #   "*.pyc"
  #   #   "__pycache__"
  #   #   "node_modules/"
  #   #   "result"
  #   # ];
  # };
}