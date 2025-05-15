{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    ### GUI Apps
    librewolf         # Privacy-focused browser
    telegram-desktop  # Messaging
    gimp             # Image editor
    blender          # 3D modeling
    virt-manager     # VM GUI (for QEMU)
    amnezia-vpn-client

    ### Media (GUI)
    mpv              # Video player
    zathura          # PDF/EPUB viewer (minimal GUI)
    imv              # Image viewer
    wf-recorder      # Screen recorder
    swappy           # Screenshot editor

    ### Wayland Utilities (GUI)
    mako             # Notifications
    wlsunset         # Night light

    ### Dev
    neovim
  ];

  ### Optional: Flatpak/Portal Support
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
}