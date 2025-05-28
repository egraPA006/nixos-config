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
      nixos-update = "sudo nixos-rebuild --flake /home/egrapa/nixos-config\\#laptop switch";
    };

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      extended = true;
    };

    initContent = ''
      setopt AUTO_CD
      setopt CORRECT
      setopt CORRECT_ALL
      setopt INTERACTIVE_COMMENTS
      setopt EXTENDED_GLOB

      if [ -z "$SSH_AUTH_SOCK" ]; then
        eval "$(ssh-agent -s)" >/dev/null 2>&1
        for key in ~/.ssh/id_*(N); do
          if [ -f "$key" ] && ! [[ "$key" == *.pub ]]; then
            fingerprint=$(ssh-keygen -lf "$key" 2>/dev/null | awk '{print $2}')
            if [ -n "$fingerprint" ] && ! ssh-add -l 2>/dev/null | grep -q "$fingerprint"; then
              ssh-add "$key" 2>/dev/null
            fi
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