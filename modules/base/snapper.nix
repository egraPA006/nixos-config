{ ... }:
{
  services.snapper.configs = {
    root = {
      SUBVOLUME = "/";
      ALLOW_USERS = [ "egrapa" ];
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    };
    home = {
      SUBVOLUME = "/home";
      ALLOW_USERS = [ "egrapa" ];
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    };
    fast = {
      SUBVOLUME = "/data/fast";
      ALLOW_USERS = [ "egrapa" ];
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    };
    slow = {
      SUBVOLUME = "/data/slow";
      ALLOW_USERS = [ "egrapa" ];
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = false;
    };
  };
}
