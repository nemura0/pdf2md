---
description: Draft an Architecture Decision Record from the repo's context
---

You are writing an ADR about: **$ARGUMENTS**

## Before writing

1. Read `docs/adr/0000-template.md` for the format.
2. Read the existing ADRs. The new decision may contradict or supersede one, and that
   has to be said explicitly.
3. Find the next sequential number.

## Rules

- **Write the Context before knowing the answer.** If you already know what you will
  choose, the ADR becomes an after-the-fact justification and loses its value.
- **At least two real options.** Each needs genuine advantages, not a dismissal.
- **Use measurements when they exist.** A probe's numbers beat an argument.
- **"What would invalidate this decision" is mandatory**, with observable conditions.
- **State the cost of reverting.** If it is high, name the point of no return.

## When done

Create `docs/adr/NNNN-<slug>.md`, and show a three-line summary: the decision, the main
reason, and the cost of reverting.
