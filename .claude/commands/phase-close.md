---
description: Verify a phase's exit criteria and prepare the next one
---

You are closing phase **P$ARGUMENTS**.

## Verification

1. Read `docs/PLAN.md` and find this phase's gate.
2. Verify each criterion **by running something**. Do not declare it met by reading code.
   If a criterion can't be verified by running something, it is badly written and must be
   fixed before closing.
3. Run the full battery from the repo root:
   - `make build test lint`
   - the `perf-gate` agent, if the phase touched `Pipeline/`, `Extract/` or `Runtime/`
   - the `pipeline-reviewer` agent, for the same paths
   - `bash scripts/e2e.sh`, once it exists
4. Check that every ADR the phase needed is `accepted`, not `proposed`, and that the ADRs
   still describe what the code does.

## Report

Produce a table: criterion | verified with | result. Green or red, nothing in between.

**If anything is red, the phase does not close.** Do not propose moving on with debt.

## If everything is green

1. Update the status in `docs/PLAN.md`.
2. Commit with Conventional Commits and push once. Watch CI once with `gh run watch`.
   Do not loop on it.
