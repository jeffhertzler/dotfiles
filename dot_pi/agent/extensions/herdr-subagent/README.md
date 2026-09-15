# Subagent Result retention

A Task's completion, Result delivery, and tab cleanup are separate events.

- `finish_task` saves the child's final Result.
- An active `subagent_wait` claims that Result. Otherwise the parent receives an automatic follow-up, which Pi may queue before saving it to the transcript.
- Successful autonomous tabs close automatically. Interactive, failed, and cancelled tabs remain available for review.
- `subagent_wait` also retrieves saved terminal Results. It works after automatic delivery, explicit close, and parent reload or restart. Repeated retrieval does not enqueue another follow-up.
- `subagent_close` closes a terminal tab, not its Result. Closing an already-cleaned Task succeeds without contacting Herdr. An active Task must finish or be cancelled first.

Results report whether cleanup is automatic, required, or already complete. If automatic cleanup fails, a later wait reports that explicit cleanup is required.

## Storage and ownership

Private Task records live under `~/.pi/agent/subagents/<task-id>/`, or the equivalent `PI_CODING_AGENT_DIR`. The directory is mode 0700; the manifest and Result files are mode 0600.

Closing a tab removes the transient state file but retains `task.json` and the full `result.json`. Cleaned records do not appear in the active-task widget. Reports larger than 48 KiB are bounded in tool output, with a path to the full saved Result until it expires.

## Retention policy

The default retention window is **30 days**. Configure it in `~/.pi/agent/subagents/retention.json`, managed by `dot_pi/agent/subagents/retention.json`:

```json
{
  "retentionDays": 30
}
```

Use a positive whole number of days, or `0` to disable automatic artifact deletion. Invalid configuration skips cleanup with a warning rather than reverting to a destructive default. Changes take effect on the next sweep without reloading.

A Task becomes eligible only when it is terminal, its tab has been cleaned up, and its final report is confirmed in the **saved parent transcript on disk**. A queued follow-up or a `delivered` flag is not enough. The retention window begins when cleanup first observes these conditions, not at launch, first delivery, or file mtime.

Once eligible for the configured number of days, cleanup removes the full Result and its owned child conversation JSONL. It also requires those files to have been unmodified for that many days. Active, interrupted, uncollected, and still-open Tasks are protected. Parent and unrelated conversations are never deleted. If a former child's conversation is referenced as another Task's parent, it is protected too.

The small `task.json` receipt remains, including ownership, status, and expiry time. This lets `subagent_close` remain idempotent and distinguishes an expired Result from an unknown Task. `subagent_wait` then returns the report saved on the current parent branch with an expiry notice. For oversized Results, that saved report may be truncated; the full report is no longer available after expiry. If the parent report is unavailable, wait reports that explicitly and does not rerun the child.

Cleanup runs at session start and, at most once per day per parent process, when the agent settles. It is opportunistic, not a timer service. Successful automatic cleanup is quiet.

- `/subagent-prune` previews due Task IDs and counts without changing any files or starting retention clocks.
- `/subagent-prune --apply` runs the same policy immediately, bypassing the daily throttle. It does not force young or protected Tasks to expire.

Older records gain their parent transcript location when that parent is resumed. They receive a fresh retention window when first confirmed eligible. Historical child transcripts whose Task records were deleted by the old extension are not swept because ownership cannot be verified safely. Missing or unverifiable parent history also prevents cleanup.

Task operations enforce the launching parent session and branch. A terminal wait can read the durable record even when the Task is no longer in the active in-memory map.

For pre-fix Tasks whose records were deleted, wait can recover a Result already present in a `subagent_result` message or successful `subagent_wait` result on the current branch. If neither the record nor that saved message exists, it reports that no saved Result is available. It does not rerun the child or infer completion from changed files.

## Regression coverage

Run from the dotfiles repository root:

```sh
tsx --test tests/*.test.ts
```

The tests cover late waits, queued-but-not-recorded delivery followed by restart, repeat retrieval, terminal close, concurrent automatic/explicit cleanup, branch and session ownership, cancelled Tasks, large reports, and recovery of pre-fix transcript Results. Retention tests use temporary stores and controlled timestamps to exercise expiry, preview, configuration, ownership checks, and protection of unrelated histories.

Canonical issue: [dotfiles #8](https://github.com/jeffhertzler/dotfiles/issues/8). The linked papercut IDs are reproduction history, not separate fixes.
