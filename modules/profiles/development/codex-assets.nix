{ config, ... }:
{
  home-manager.users.${config.pino.user.name} = {
    home.file.".codex/AGENTS.md" = {
      source = ../../../AGENTS.md;
    };

    home.file.".codex/agents" = {
      source = ../../../codex/agents;
      recursive = true;
    };

    home.file.".codex/skills" = {
      source = ../../../codex/skills;
      recursive = true;
    };
  };
}
