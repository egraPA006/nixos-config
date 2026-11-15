---
name: agent-routing
description: Choose models and spending preferences for subagent roles in research, develop or bounded delegation; update the shared model lineup when requested. Does not start a full team by itself.
---

# Roles and model selection

Roles define duties, permissions and independence; models are selected per assignment.
Read [the shared catalog](references/models.json) only when selecting or updating models.
Research/develop own orchestration; this skill supplies their common selection policy.
Do not delegate routine tasks automatically. Delegate only when the user asks or an
explicitly invoked workflow skill requires it.
Use [task-runner](../../agents/task-runner.toml) for agreed commands/scenarios and
[expert-advisor](../../agents/expert-advisor.toml) for a final expert pass inside research/develop only.
Existing research/develop roles retain their duties. Use named roles when supported,
otherwise pass their instructions with an ordinary fresh worker. No recursive delegation.

## User preferences and models

Respect explicit model, quality and cost preferences by role, without persisting task preferences. Use only models available to the current runtime and authorized provider; do not silently switch to a paid route. Availability varies by installation and subscription. The shared catalog contains historical candidate IDs, not a guarantee that these models are available. If a preferred model cannot be selected, disclose this and use a user-authorized fallback.

| Tier | Typical use | Candidate subscription model |
| --- | --- | --- |
| simple | bounded commands or lookups | gpt-6-luna |
| standard code | implementation | gpt-6.1-terra |
| standard analysis, review, coordinator | analysis and review | gpt-6.1-sol |
| deep and expert | final assessment | gpt-6-astra |

Choose supported exact IDs and fresh context. Record requested and runtime-confirmed identity separately. Do not claim a model is unavailable merely because it is absent from an example list; distinguish actual launch failures from unverified availability. Follow explicit user choices.

## Reasoning and expert escalation

User-specified effort takes precedence. Default all roles to medium, including
coordinator, researcher, developer, tester, reviewer and expert; task-runner defaults
to low. Use that supported value explicitly at launch rather than relying on inherited
parent effort. The global subagent default is medium; pass low for each runner.
Raise to high for a concrete difficult question when useful, within task preferences
and budget; coordinator/expert titles alone do not justify higher effort. Levels above
high are exceptional, not defaults. Stop increasing effort once evidence is sufficient.

Read supported levels from the current model/runtime; do not invent parameter names
or levels, or map another provider's reasoning setting blindly. If effort control is
absent, retain its runtime default and disclose that limitation when material. Record
requested effort with the selected ID in the plan; do not claim it was applied without
runtime confirmation. This does not change the main-chat model/reasoning choice.

A coordinator may adjust its effort for later turns only if the runtime supports it.
Otherwise, inside research/develop it can request higher effort from the relevant
worker; reserve the expert for the final gate unless the user explicitly asks earlier.
The final expert runs without restarting the coordinator,
creating another coordinator or copying the entire parent chat. Within the existing
route, permissions, slots and spending budget, this needs no additional user approval.
The coordinator retains decisions; final expert advice does not replace independent review.

## Budget and escalation

- Execute a trivial command directly when delegation would cost more than it saves.
- Give workers only the task, relevant evidence, permissions, acceptance criterion,
  relevant skill/role instructions and a short expected answer. Keep critics independent.
- Filter/search logs with tools before model input. Wait on processes using runtime
  wait/notifications; avoid repeated model turns just to ask if a build finished.
- A runner executes an agreed command/scenario on an assigned target. Choosing an
  image, recovery strategy or new diagnosis may require standard/deep reasoning.
- After a substantive failure, stop blind retries and send evidence to the coordinator.
  It may upgrade within the same allowed route and budget; changing route, exceeding
  an explicit spending limit or relaxing permissions requires user authorization.
- Bound specialist output and rounds. Choose one expert for a concrete open question;
  do not copy the entire conversation or create advisory agents without a useful task.
  Experts are confined to research/develop and their final gate; ordinary delegation
  never adds an expert automatically.

Reverse engineering and security analysis are research tracks, not separate model
classes. Describe the actual authorized objective and scope. Any report condensation
must preserve purpose, material context, uncertainty and evidence; never conceal them
or rephrase to bypass another model's refusal. An ordinary research worker can handle
such a track within its permissions.

## Shared workflow operation

Research/develop each have standard and pro modes; there is no diagnostic-only mode.
Use research for investigation without production edits, develop for implementation;
explicit user scope/validation instructions still win. Seven roles: coordinator,
runner, researcher, developer, tester, reviewer, expert. Reviewer can interview before
seeing reports and verify a final draft; a fresh final reviewer is a separate agent
of the same role. Do not reuse a source-exposed reviewer as a fresh blind verifier.

Workflow budgets in the individual skills are planning targets, not runtime guarantees.
Respect the actual agent and concurrency limits reported by the current runtime, even
when they are lower than a workflow's preferred team size. Do not probe capacity with
dummy agents. If a required role cannot be run, report the reduced independent
coverage instead of claiming the full workflow completed.

Run until acceptance and final checks succeed, up to 10 substantive rounds in standard
mode or 20 in pro. A round is new evidence resolving a question or an implementation/
review/correction cycle; waits, tool calls and mechanical execution retries are not
rounds. Final expert correction cycles count within the same limit, not a new budget.
After two rounds with no decision-changing progress, change approach; if still blocked,
report the concrete blocker. At the cap return achieved results, open issues and the
smallest next step, asking before more rounds. Never stop solely because a fixed
number of rounds passed if criteria were already met earlier; never declare unfinished
work complete. Reuse suitable workers rather than spawning a team each round.

Workers return their result and then wait for a real follow-up. They must not poll
other workers, repeatedly ask for status or send empty keepalives. Coordinator waits
on completion notifications or a blocking wait; after a timeout it waits again without
status chatter or inspecting every worker. When a tool requires timed waits, use a
meaningful supported timeout, not a tight loop of model turns. Process/hardware health
checks required by the actual task remain allowed. Report meaningful progress to the
user, not every wait timeout.

## Final expert gate

Once implementation/research and ordinary checks/review are ready, launch one fresh
expert with medium effort; defaults: coordinator and reviewer=gpt-6.1-sol,
expert=gpt-6-astra. User model/route preferences override these defaults. Do not launch
an expert automatically during intermediate rounds. A user may explicitly request an
earlier consultation; do not infer that exception from routine difficulty.

Give the expert the original task/corrections and restrictions, exact final diff or
report, source/evidence pointers, actual validation and unresolved limitations. Omit
author persuasion, previous verdicts and debate history. Require concrete correctness,
intent, contradiction and evidence findings, not cosmetic preferences. The expert
stays read-only and does not become another coordinator.

For material findings, coordinator assigns fixes to their owner, tester/reviewer repeat
affected checks, then the same expert rechecks the changed final artifact. Reuse is a
follow-up, not another fresh blind review. Reviewer and expert do not need to agree by
vote: resolve through evidence, scope or a genuine user decision. At access/round limits
report unresolved findings and the missing gate rather than claiming completion.
For review-only, report findings without editing or starting implementation. No gate
grants new authorization for devices, network, installation, commit or publication.

## Updating models

When explicitly asked to update model choices, inspect the models actually available through the current runtime and update the shared catalog. Do not access credentials or run paid requests just to populate it. Do not install or modify live configuration without an explicit request.
