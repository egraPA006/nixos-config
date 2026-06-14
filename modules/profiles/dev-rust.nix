{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    rustup
    cargo-watch
    cargo-edit
    cargo-audit
  ];
}
