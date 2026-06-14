{ hostname, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };

    "org/gnome/desktop/background" = {
      picture-uri = "file:///home/egrapa/nixos-config/home/wallpaper-${hostname}.jpg";
      picture-uri-dark = "file:///home/egrapa/nixos-config/home/wallpaper-${hostname}.jpg";
      picture-options = "zoom";
    };

    "org/gnome/shell" = {
      favorite-apps = [
        "org.gnome.Terminal.desktop"
        "chromium-browser.desktop"
        "org.gnome.Nautilus.desktop"
        "org.telegram.desktop.desktop"
      ];
      enabled-extensions = [
        "clipboard-history@alexsaveau.dev"
        "tiling-assistant@leleat-on-github"
      ];
    };
  };
}
