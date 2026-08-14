{ config, ... }:

{
  home-manager.users.${config.pino.user.name}.programs.codex = {
    enable = true;

    settings = {
      model_reasoning_effort = "medium";

      approval_policy = "on-request";
      approvals_reviewer = "auto_review";
      sandbox_mode = "workspace-write";

      web_search = "cached";

      sandbox_workspace_write = {
        network_access = false;
      };

      projects = {
        "${config.pino.user.home}/prog/nvim-config" = {
          trust_level = "trusted";
        };

        "${config.pino.configDir}" = {
          trust_level = "trusted";
        };
      };
    };

    context = ''
      # Global Codex instructions

      - Inspect relevant files before editing.
      - Prefer small, focused changes.
      - Preserve existing architecture and code style.
      - Do not modify unrelated files.
      - Do not discard existing user changes.
      - Check git diff before finishing.
      - Do not commit or push unless explicitly requested.
      - Ask before destructive operations.
      - Never print, copy, or commit secrets.

      For C and C++:
      - Be explicit about ownership, lifetime, signedness, and conversions.
      - Follow existing project conventions.
      - Avoid unnecessary abstractions and allocations.

      For Linux, Embedded, and Android:
      - Consider cross-compilation.
      - Distinguish userspace, kernel, firmware, HAL, and framework behavior.
      - For Android, consider Soong, init, SELinux, Binder, permissions, and API level.
      - Never weaken SELinux as a final solution.
    '';

    rules = {
      git = ''
        prefix_rule(
          pattern = ["git", "push"],
          decision = "prompt",
          justification = "Pushing changes requires explicit confirmation.",
        )

        prefix_rule(
          pattern = ["git", "reset", "--hard"],
          decision = "forbidden",
          justification = "Avoid destroying uncommitted work.",
        )

        prefix_rule(
          pattern = ["git", "clean"],
          decision = "forbidden",
          justification = "Avoid deleting untracked files.",
        )
      '';
    };
  };
}
