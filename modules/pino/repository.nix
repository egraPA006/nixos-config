{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.git ];

  programs.ssh = {
    systemd-ssh-proxy.enable = false;
    knownHosts.github = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
  };
}
