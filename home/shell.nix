{ pkgs, config, ... }:

{
  imports = [
    ./configs/git.nix
  ];
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -lha --color=auto";
      la = "ls -A --color=auto";
      l = "ls -CF --color=auto";
      grep = "grep --color=auto";
      fgrep = "fgrep --color=auto";
      egrep = "egrep --color=auto";
      ssh = "TERM=xterm-256color ssh";
      nixos-update = "sudo nixos-rebuild --flake /home/egrapa/nixospconfig#laptop switch";
    };

    history = {
      size = 10000;
      save = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      extended = true;
    };

    initContent = ''
      # Better directory navigation
      # setopt AUTO_CD
      # setopt CORRECT
      # setopt CORRECT_ALL
      # setopt INTERACTIVE_COMMENTS
      # setopt EXTENDED_GLOB

      # SSH Agent setup
      if [ -z "$SSH_AUTH_SOCK" ]; then
        eval $(ssh-agent -s) > /dev/null
        for key in ~/.ssh/id_*; do
          if [ -f "$key" ] && ! ssh-add -l | grep -q "$(ssh-keygen -lf $key | awk '{print $2}')"; then
            ssh-add "$key" 2>/dev/null
          fi
        done
      fi
    '';
  };
  home.packages = with pkgs; [
    bat    
    fd
    ripgrep
    neofetch
  ];
}