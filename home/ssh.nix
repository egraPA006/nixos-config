{ ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."github.com" = {
      IdentityFile = "/home/egrapa/.ssh/github_ed25519";
      IdentitiesOnly = true;
    };
  };
}
