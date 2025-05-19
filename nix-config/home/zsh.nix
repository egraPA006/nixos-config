{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;

    # Set as default shell
    # shellInit = ''
    #   # Set ZSH as default shell
    #   [ -f ~/.zshrc ] || touch ~/.zshrc
    #   export SHELL=${pkgs.zsh}/bin/zsh
    # '';

    # Basic configuration
    # ohMyZsh = {
    #   enable = true;
    #   plugins = [ "git" "sudo" "fzf" "direnv" ];
    #   theme = "robbyrussell"; # Simple classic theme
    # };

    # Local configuration
    initExtra = ''
      # SSH Agent setup
      if [ -z "$SSH_AUTH_SOCK" ]; then
        eval $(ssh-agent -s) > /dev/null
        for key in ~/.ssh/id_*; do
          if [ -f "$key" ] && ! ssh-add -l | grep -q "$(ssh-keygen -lf "$key" | awk '{print $2}')"; then
            ssh-add "$key" 2>/dev/null
          fi
        done
      fi

      # Basic aliases
      alias ls='ls --color=auto'
      alias ll='ls -lah'
      alias grep='grep --color=auto'
      alias df='df -h'
      alias du='du -h'
      alias mkdir='mkdir -p'
      alias vim='nvim'
      
      # Ranger with image preview
      alias ranger='ranger --cmd="set preview_images_method ueberzug"'
      
      # Quick directory navigation
      alias ..='cd ..'
      alias ...='cd ../..'
      
      # Git shortcuts
      alias gs='git status'
      alias ga='git add'
      alias gc='git commit'
      alias gp='git push'
      
      # Use bat for man pages
      export MANPAGER="sh -c 'col -bx | bat -l man -p'"
      
      # FZF configuration
      export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
      export FZF_DEFAULT_COMMAND='fd --type f'
      
      # History settings
      HISTSIZE=10000
      SAVEHIST=10000
      HISTFILE=~/.zsh_history
      setopt appendhistory
      setopt sharehistory
      setopt incappendhistory
      
      # Better directory navigation
      setopt autocd
      setopt extendedglob
      setopt nomatch
      setopt notify
      
      # Key bindings
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down
      bindkey '^R' history-incremental-search-backward
    '';
  };

  # Ensure zsh is default shell
  users.users.egrapa = {
    shell = pkgs.zsh;
  };

  # Required packages
  home.packages = with pkgs; [
    bat
    fd
    git
    man-pages
    man-pages-posix
  ];

  # SSH agent service
  # programs.ssh.startAgent = true;
  services.gpg-agent = {
    enable = true;
    enableZshIntegration = true;
  };
}