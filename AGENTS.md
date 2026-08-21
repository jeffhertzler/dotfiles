## Tests

Run the complete TypeScript suite from the repository root with:

```sh
tsx --test tests/*.test.ts
```

This is the authoritative test command. The TSX loader resolves the runtime
dependencies used by the managed Pi extensions; `bun test` and plain
`node --test` do not exercise the suite correctly.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`jeffhertzler/dotfiles`), accessed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo with `CONTEXT.md` and `docs/adr/` at the root. See `docs/agents/domain.md`.
