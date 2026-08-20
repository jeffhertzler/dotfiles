# Domain docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root.
- **`docs/adr/`** for ADRs that touch the area you're about to work in.

If either location doesn't exist, proceed silently. Don't flag its absence or suggest creating it upfront. The `/domain-modeling` skill, reached through `/grill-with-docs` and `/improve-codebase-architecture`, creates domain docs when terms or decisions get resolved.

## File structure

This is a single-context repo:

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

## Use the glossary's vocabulary

When your output names a domain concept in an issue title, refactor proposal, hypothesis, or test name, use the term defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the glossary doesn't cover a concept you need, reconsider whether you're inventing language the project doesn't use. If the gap is real, note it for `/domain-modeling`.

## Flag ADR conflicts

If your output contradicts an existing ADR, say so rather than silently overriding it:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because..._
