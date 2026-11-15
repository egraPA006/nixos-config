---
name: develop
description: Development with independent test design and review, from investigation to verified results. Use for explicit requests to develop with independent review, a developer/tester/reviewer team, or $develop (including pro mode). Also supports review-only of an existing change; ordinary small edits do not trigger the full team.
---

# Develop with independent review

## Isolated coordinator handoff

The main chat is a relay, not the workflow coordinator. Before substantive work,
spawn one fresh [workflow coordinator](../../agents/workflow-coordinator.toml)
with `fork_turns="none"`. Resolve its model and supported reasoning effort through
[agent-routing](../agent-routing/SKILL.md): default `gpt-6.1-sol` at medium; explicit user
preferences take precedence. Pass:
- the original task text and applicable user corrections, preserving wording;
- explicit permissions/prohibitions, requested validation mode, budget and output;
- task-wide and per-class model/route/cost preferences, preserving user wording;
- exact workspace/source/device scope, relevant AGENTS.md, current factual state
  and pointers to necessary files/artifacts;
- this skill path, role `workflow-coordinator`, mode research or develop, and the
  actual shared slot/tool limits, including already occupied slots.
Exclude conversation history, parent hypotheses, proposed solutions, prior verdicts
and persuasive summaries. Prior technical conclusions are not facts: provide raw
source pointers when needed. Do not omit constraints to make the brief cleaner.
The coordinator reads this skill and executes its workflow; it does NOT spawn another
coordinator. Only the main chat performs this handoff, once per task.

The main chat forwards user corrections and coordinator questions faithfully, requests
user input when needed, and relays the result with its limitations. It does not run a
parallel investigation or quietly rewrite the coordinator's technical conclusions.
If a clear factual conflict arises, return it to the coordinator for resolution.
Coordinator may delegate workers within the shared budget, not more coordinators.
If nested spawning is unsupported, the main chat mechanically dispatches the exact
worker briefs supplied by the coordinator and forwards their reports unedited.
If a necessary tool is only available to the parent, relay an exact authorized action
and its result; the coordinator retains decisions. If isolated spawning is unavailable,
report the limitation and ask before substituting main-chat coordination.

## Brief, permissions and roles

The isolated coordinator retains the task brief, corrections, permissions and
acceptance criteria. Preserve user wording separately from inferred requirements.
Save milestones under the existing project convention; mark assumptions explicitly.

Read role developer_instructions and pass them to fresh workers:
- [Developer](../../agents/develop-developer.toml): investigate and implement.
- [Tester](../../agents/develop-tester.toml): independently design validation and write tests when permitted.
- [Reviewer](../../agents/develop-reviewer.toml): review code and outcome, read-only.
For a genuinely separate research track, reuse
[researcher](../../agents/research-researcher.toml). Do not launch the entire
research workflow inside this workflow or let workers recursively delegate.

Use supported named roles, otherwise pass instructions in the spawn message.
Use fork_turns="none" where available; do not invent unsupported tool arguments.
Use the model defaults below. Each worker gets the original request and corrections,
explicit permissions, applicable AGENTS.md constraints, assigned files and source
scope. Permissions are never broadened by delegation.
Keep reviewer and tester initial briefs free of the author's preferred solution.
If fresh context or delegation is unavailable, disclose the limitation.

## Team budget

- Standard: main chat + coordinator + developer + independent tester + reviewer
  + final expert = six agents.
- Pro: main chat + coordinator + two developers with nonoverlapping production
  ownership + independent tester + reviewer + fresh final reviewer + final expert
  = eight agents. Split implementation only when useful; never invent duplicate work.
- Reviewer and coordinator default to Sol, final expert to Astra, all at medium.
  User preferences and agent-routing override these defaults. Reserve independent
  checks and the final expert before optional researchers/runners; task ceiling 16.
- Tester remains useful in no-new-tests mode for target scenarios/evidence. Do not
  merge it into the developer/reviewer because of assumed capacity.
- Review-only uses main chat + coordinator + reviewer + final expert; add a tester
  only for useful permitted checks. Review alone authorizes no fixes.

Investigations without implementation use research, not a separate diagnostic mode.
An explicit develop request remains develop, but cannot authorize production edits
when the user prohibited them; clarify only a genuine scope conflict.
A follow-up by an existing reviewer/expert is not a fresh blind review.

## Capacity and scheduling

Workflow budgets below count the main chat, coordinator and every worker, including
completed workers if the runtime retains them. These are task budgets, not claims
about runtime capacity. Do not infer a four/five-agent limit from these skills.
Use a limit only when explicitly declared by the current runtime/config or returned
by an actual spawn rejection; configuration is a requested setting, not proof that
an existing session adopted it. Inventory existing workers when supported and reuse
suitable workers within their role. Never count idle/completed/interrupted as released
unless the runtime documents or confirms that. Use close/release only if available.

With no declared limit, attempt the planned useful workers within the workflow budget;
do not create dummy agents to probe capacity. On an actual capacity rejection, record
which launch failed and preserve completed work. Retry only after a real capacity
change, not repeatedly against the same state. A context-depth/tool/permission error
is not a slot error: use the parent dispatch relay when appropriate. When explaining
an omitted role, distinguish runtime-declared limit, observed spawn rejection,
user/task budget, unavailable release and an unattempted launch. Never report
"ran out of slots" for a launch you merely chose not to attempt.

Reserve capacity for required independent roles before adding optional researchers.
If the declared capacity cannot fit the requested team and release is unavailable,
report the exact conflict and ask before reducing promised independence. An unexpected
rejection may leave partial results, but does not authorize calling a reduced run
complete. Never turn a source-exposed worker into a fresh independent verifier.

## Model selection

Use [agent-routing](../agent-routing/SKILL.md) and its single shared catalog.
Role defines responsibilities; choose model separately by assignment tier and the
user's class/route/cost/quality preferences. Main chat model and global config.toml
are irrelevant. Resolve coordinator choice before handoff; coordinator chooses workers.
Include role/class, tier, selected ID, route and requested effort in the brief/plan, not a new approval
round for each worker. Keep the required independent roles regardless of model choice.
Consult the catalog at selection time; do not duplicate model tables in this skill.
Follow agent-routing for waiting without polling, 10/20-round limits and the final
expert gate. Intermediate rounds use the ordinary workers/reviewer; final expert is
Astra at medium by default, after the artifact and ordinary checks are ready.

## Validation mode

User instructions override the default test-writing workflow. «Без тестов» or
«не пиши тесты» means do not create or modify automated tests, fixtures or test
harnesses, including temporary substitutes. It does not by itself prohibit running
existing checks. «Только на девайсе/целевой среде» limits validation to that target
and necessary build/deployment steps; «не запускай тесты» also forbids test execution.
Carry the exact chosen mode into every worker's brief.

In no-new-tests mode the tester designs manual/target scenarios and evaluates their
results; the developer writes no tests either. Use existing tools and direct commands,
not new test scripts disguised as diagnostics. Reviewer assesses evidence for the
chosen mode and must not demand automated tests merely as a policy. Report concrete
uncovered risks. Target validation can be sufficient when it covers acceptance criteria;
absence of automated tests alone is not a failure. If the target is unavailable, leave
those criteria unverified rather than silently switching validation modes.

## Development cycle

Use the agreed role sequence below. A capacity conflict is handled explicitly
under Capacity and scheduling, not by silently omitting the tester or reviewer.

1. Investigation: developer inspects existing code and reuse options. In parallel,
   tester derives scenarios from the request and existing test infrastructure;
   reviewer derives acceptance questions from the original brief before seeing diff.
   Coordinator records criteria, assumptions and the smallest useful implementation.
2. Implementation: developer owns production edits; tester owns explicitly assigned
   test files. Serialize overlapping edits, shared fixtures/configuration, builds and
   device operations. Respect unrelated work; separate output trees where necessary.
   Tester may inspect interfaces/code after independently defining expectations.
3. Tests: use behavior-based checks, boundaries, failures and relevant regressions.
   For bug fixes demonstrate failure before and success after where practical using
   isolated artifacts; never reset a dirty checkout to obtain a baseline. Explain
   unavailable baselines. Do not add tests mirroring implementation or trivial edits.
   Do not weaken assertions solely to make the implementation pass.
4. Code review: reviewer receives original brief, diff, relevant surrounding code
   and test artifacts, without an author's persuasive summary. Check correctness,
   regressions, test adequacy and contradictions with the request. Findings need a
   concrete failure, impact and source; hypothetical preferences are not blockers.
5. Execution: coordinator runs or explicitly assigns authorized cheap checks, builds
   and device scenarios using applicable tools and skills. Devices must be assigned;
   observe leases and task restrictions.
   Expensive tests/network access still need existing authorization. Test-writing
   authority is not permission to flash hardware or change external services.
6. Outcome review: reviewer compares each acceptance criterion with actual evidence:
   code revision or dirty-diff identity, build artifact, device identity/version,
   command/scenario, observed result and remaining gaps. A passing build or mock is
   not proof of device behavior. Unavailable hardware is unverified, not passed.
7. Final gate: when the implementation, tests and outcome review are ready, pro mode
   first gives the final artifact/evidence to its fresh final reviewer. Then launch
   the expert from agent-routing with original requirements, exact diff/artifact and
   actual checks/limitations, without previous verdicts or persuasion.
8. Correction: return actionable findings to their owner. Re-run affected checks
   after changes and broaden when new risks justify it. Earlier results do not prove
   a changed artifact works. After material expert findings, ordinary review/tests run
   again on affected scope before the same expert rechecks the revised final artifact.
   Use the shared 10-round standard / 20-round pro limit, including expert corrections;
   stop earlier when criteria and final checks pass. At the limit report open
   issues and the smallest next step; never claim completion because time ran out.

Keep a compact criterion → check → evidence → status table in the plan/REVIEW.md,
not raw agent dialogue. Resolve disagreements through evidence or a real user
clarification, never by vote or by impersonating user preferences. Report achieved
behavior, validation and remaining limitations in Russian. Commit, push and install
remain separate authorization decisions under the existing rules.

## Review-only

For a requested review of an existing change, identify its exact diff layer and
original task, then use reviewer for steps 4 and 6, followed by the final expert gate. If the task is unavailable,
review code correctness and explicitly leave intent compliance unverified. Add a
tester only for useful independent validation. Review alone authorizes no fixes;
report findings and permitted check results without starting implementation.
