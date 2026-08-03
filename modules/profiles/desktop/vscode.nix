{ config, pkgs, ... }:

{
  home-manager.users.${config.pino.user.name} = {
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;
      mutableExtensionsDir = true;
      profiles.default.extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
      ];

      profiles.default.userSettings = {
        "editor.fontSize" = 14;
        "editor.tabSize" = 2;
        "editor.formatOnSave" = true;
        "editor.minimap.enabled" = false;
        "workbench.colorTheme" = "Default Dark+";
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "claude-code.executablePath" = "/etc/profiles/per-user/${config.pino.user.name}/bin/claude";
      };
    };

    home.packages = with pkgs; [ nil ];
  };
}
