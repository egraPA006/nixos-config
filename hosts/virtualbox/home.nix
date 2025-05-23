{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    # ./neovim.nix
    # ./sway.nix
    # ./zsh.nix
    ../../home/plasma.nix
  ];

  # Basic Home Manager settings
  home = {
    username = "test";  # Replace with your actual username
    homeDirectory = lib.mkForce "/home/test";
    stateVersion = "24.11";     # Match your NixOS version

    # Packages that should be installed specifically for the user
    packages = with pkgs; [
      # Add any user-specific packages here
      # (most should be in system.nix or utilities.nix)
    ];
  };

  # Enable Home Manager
  programs.home-manager.enable = true;

  # GTK/Qt theming (optional but recommended for Sway)
  # gtk.enable = true;
  # qt.enable = true;

  # XDG Desktop Portal configuration (required for Wayland)
  # xdg = {
  #   enable = true;
  #   portal = {
  #     enable = true;
  #     extraPortals = with pkgs; [
  #       xdg-desktop-portal-wlr
  #       xdg-desktop-portal-gtk
  #     ];
  #   };
  # };

  # Systemd services for user session
  # services = {
  #   # SSH agent (complements your zsh.nix setup)
  #   ssh-agent.enable = true;

  #   # GPG agent for password management
  #   gpg-agent = {
  #     enable = true;
  #     pinentryFlavor = "gtk2";
  #     enableSshSupport = true;
  #   };
  # };

  # Dotfile management
  # home.file = {
  #   # Example: Manage a specific config file
  #   ".config/example.conf".text = ''
  #     # Config file content
  #   '';
  # };

  # Environment variables
  # home.sessionVariables = {
  #   EDITOR = "nvim";
  #   VISUAL = "nvim";
  #   TERMINAL = "kitty";
  #   BROWSER = "firefox";
  # };

  # Let Home Manager install and manage itself
}