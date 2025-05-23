{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;

    shellAliases = {
      ll = "ls -lha";
      g = "git";
      grep = "grep --color=auto";
      ssh = "TERM=xterm-256color ssh";  # Fix colors in SSH sessions
    };

    history = {
      size = 10000;
      save = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      extended = true;
    };

    initExtra = ''
      # Better directory navigation
      setopt AUTO_CD
      setopt CORRECT
      setopt CORRECT_ALL
      setopt INTERACTIVE_COMMENTS

      # SSH Agent setup
      if [ -z "$SSH_AUTH_SOCK" ]; then
        eval $(ssh-agent -s) > /dev/null
        for key in ~/.ssh/id_*; do
          if [ -f "$key" ] && ! ssh-add -l | grep -q "$(ssh-keygen -lf $key | awk '{print $2}')"; then
            ssh-add "$key" 2>/dev/null
          fi
        done
      fi

      # Colorful man pages
      export LESS_TERMCAP_mb=$'\e[1;32m'
      export LESS_TERMCAP_md=$'\e[1;32m'
      export LESS_TERMCAP_me=$'\e[0m'
      export LESS_TERMCAP_se=$'\e[0m'
      export LESS_TERMCAP_so=$'\e[01;33m'
      export LESS_TERMCAP_ue=$'\e[0m'
      export LESS_TERMCAP_us=$'\e[1;4;31m'
    '';
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
    zsh
    zsh-completions
    zsh-syntax-highlighting
    zsh-autosuggestions
    btop
    bat  # Cat with syntax highlighting
  ];

  # Make ZSH the default shell
  programs.bash.enable = false;
  home.sessionVariables = {
    SHELL = "${pkgs.zsh}/bin/zsh";
  };
}