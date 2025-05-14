{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    kitty
    zsh
    zsh-syntax-highlighting
    zsh-autosuggestions
    fzf
    btop
    wl-clipboard
  ];

  programs.zsh.enable = true;
}