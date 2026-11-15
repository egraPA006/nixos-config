{ config, pkgs, ... }:

let
  codexExtension = pkgs.vscode-utils.extensionFromVscodeMarketplace {
    publisher = "openai";
    name = "chatgpt";
    version = "26.51111.21308";
    arch = "linux-x64";
    sha256 = "4bd5b7ed27c46ac356a4129aa8dbc2b316ddd8407cc4d8996e3b7d17e7c5b4ac";
  };
in
{
  home-manager.users.${config.pino.user.name} = {
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;
      mutableExtensionsDir = true;
      profiles.default.extensions = [
        pkgs.vscode-extensions.jnoortheen.nix-ide
        codexExtension
      ];

      profiles.default.userSettings = {
        "editor.fontSize" = 14;
        "editor.tabSize" = 2;
        "editor.formatOnSave" = true;
        "editor.minimap.enabled" = false;
        "workbench.colorTheme" = "Default Dark+";
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
      };
    };

    home.packages = with pkgs; [ nil ];
  };
}
