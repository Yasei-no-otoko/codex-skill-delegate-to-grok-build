---
name: delegate-to-grok-build
description: Delegate bounded software tasks to the locally installed xAI Grok Build CLI and verify its work. Use when the user asks Codex to use Grok, Grok Build, or xAI as a subagent or second opinion, or when an independent codebase review, repository exploration, implementation patch, or focused diagnosis is useful. Supports read-only and workspace-editing headless runs on Windows while keeping commits, pushes, destructive commands, memory, and nested subagents outside the delegated scope.
---

# Delegate to Grok Build

Use Grok Build as an external worker for one clearly bounded task. Keep ownership of planning, safety, verification, and the final answer in Codex.

## Delegate safely

1. Read the target repository's instructions and inspect its current Git state before delegating.
2. Choose a task with a concrete goal, scope, constraints, and required evidence. Prefer independent review, exploration, diagnosis, or a small implementation slice.
3. Tell the user briefly that Grok Build is being used and what it will handle.
4. Select a mode:
   - `Review`: allow only Grok's file listing, read, and search tools. Use for audits, explanations, planning, and second opinions.
   - `Edit`: also allow file edits inside the selected working directory. Use only when the user has authorized implementation. Shell commands remain denied; Codex performs tests and other verification.
5. Invoke `scripts/invoke-grok-build.ps1`; do not call `grok` directly unless the wrapper is unavailable.
6. Inspect Grok's report and independently verify every material claim. In `Edit` mode, inspect the diff and run appropriate tests yourself.
7. Integrate only useful results. Grok's output is evidence, not authority.

Do not delegate secrets, credential handling, production changes, remote messages, releases, commits, pushes, tags, or destructive cleanup. Do not use Grok to broaden the user's requested scope. The wrapper disables Grok memory, nested subagents, auto-update, and unrequested web search.

## Build the delegation prompt

Include all of the following:

- the exact outcome to produce;
- the repository or file scope;
- relevant symptoms, constraints, and existing user changes to preserve;
- whether edits are allowed;
- the checks Grok should perform;
- the requested report shape: summary, evidence or changes, verification, and blockers.

Do not paste the entire parent conversation. Pass only task-local context. For independent review, do not reveal the suspected answer or desired finding.

## Invoke the worker

Run a read-only review:

```powershell
& "<skill-directory>\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory "C:\path\to\repo" `
  -Mode Review `
  -MaxTurns 10 `
  -TimeoutSeconds 300 `
  -Prompt "Inspect the authentication flow for concrete defects. Cite files and line numbers. Do not edit files."
```

Run a bounded edit:

```powershell
& "<skill-directory>\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory "C:\path\to\repo" `
  -Mode Edit `
  -Prompt "Fix the null handling in src/parser.ts only. Preserve unrelated changes. Report changed files and verification."
```

The wrapper writes inline task text to a short-lived prompt file so it is not exposed in the process command line. For a long prompt that already exists on disk, pass it with `-PromptFile`. Use `-DenyRule` to add project-specific hard restrictions. Use `-DryRun` to inspect the generated CLI arguments without contacting Grok. Override `-Model`, `-ReasoningEffort`, `-MaxTurns`, `-TimeoutSeconds`, or `-GrokExecutable` only when the task requires it.

Web search is off by default. Add `-EnableWebSearch` only when current external information is necessary and the user permits the data involved to leave the machine.

## Verify and recover

- Treat a nonzero exit code, malformed JSON, a stop reason other than `end_turn`, missing evidence, or an incomplete edit as a failed delegation. The wrapper enforces the JSON stop-reason check and terminates the Grok process tree when its time limit is reached.
- For review output, open the cited files and reproduce the reasoning.
- For edits, compare pre- and post-run Git status, inspect every changed file, and run relevant tests. Revert or fix only Grok-authored changes; preserve pre-existing user changes.
- If authentication is missing or expired, report that `grok login` or `grok login --device-auth` must be completed. Never print, request, or persist an API key in a task prompt.
- On Windows, do not treat Grok's sandbox profile as the primary security boundary. The wrapper hard-denies shell and MCP tools, sensitive credential paths, Git metadata edits, and unrequested web tools; narrow task scope and independent verification remain required.
