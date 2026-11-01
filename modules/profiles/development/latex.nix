{ config, lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.texliveFull ];

  home-manager.users.${config.pino.user.name} = { config, ... }: {
    programs.vscode.profiles.default = lib.mkIf config.programs.vscode.enable {
      extensions = [ pkgs.vscode-extensions.james-yu.latex-workshop ];
      userSettings = {
        "latex-workshop.latex.autoBuild.run" = "onSave";
        "latex-workshop.latex.recipe.default" = "lastUsed";
        "latex-workshop.view.pdf.viewer" = "tab";
      };
    };
  };
}
