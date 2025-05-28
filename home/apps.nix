{ pkgs, inputs, ... }:

{
  home.packages = with pkgs; [
    # Web browsers

    # Media
    vlc
    mpv

    # Office
    onlyoffice-bin

    # Chat
    telegram-desktop
  ];

  programs.librewolf = {
    enable = true;
    
    settings = {
      # Dark mode settings
      "browser.theme.dark" = true;
      "widget.content.dark" = true;
      "browser.in-content.dark-mode" = true;

      # Privacy tweaks (keep cookies/history)
      "network.cookie.lifetimePolicy" = 0;  # 0=normal, 1=ask, 2=session
      "privacy.clearOnShutdown.cookies" = false;
      "privacy.clearOnShutdown.history" = false;
      "places.history.enabled" = true;

      # Disable some aggressive defaults
      "privacy.resistFingerprinting" = false;  # Better compatibility
      "privacy.trackingprotection.enabled" = false;  # Let uBlock handle this

      # Performance
      "gfx.webrender.all" = true;
      "media.ffmpeg.vaapi.enabled" = true;
    };

    # extensions = with pkgs.nur.repos.rycee.firefox-addons; [
    #   darkreader  # Dark mode for all websites
    #   ublock-origin  # Best ad blocker
    # ];
  };
}