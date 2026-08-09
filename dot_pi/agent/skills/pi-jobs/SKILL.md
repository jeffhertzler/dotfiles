---
name: pi-jobs
description: Create, inspect, update, run, schedule, disable, and remove private recurring Pi jobs managed by pi-job, systemd user timers, and Herdr. Use whenever the user asks Pi about scheduled or periodic agent work on this machine.
---

# Private scheduled Pi jobs

Use the managed `pi-job` CLI. This skill is globally available to Pi. The
mechanism is public chezmoi source, but every actual job and prompt is private
machine-local state.

## Fixed routing and retention

All jobs currently run in:

- Herdr session: `default`
- Herdr workspace: `Scheduled`
- Destination: a new unfocused tab for every occurrence
- Pi context: a fresh interactive Pi process and session for every occurrence
- Environment marker: `PI_SCHEDULED_JOB=1` in the tab and Pi process

Do not configure another Herdr session, workspace, or topology. Do not close old
job tabs, workspaces, or Pi processes automatically. The user inspects and
closes them manually; retention automation is intentionally deferred. The
marker identifies scheduled shells but does not currently suppress or alter any
shell startup configuration.

## Private and managed locations

Private job state:

```text
~/.config/pi-jobs/jobs/<name>/job.json
~/.config/pi-jobs/jobs/<name>/prompt.md
~/.config/systemd/user/pi-job-<name>.timer
~/.local/state/pi-jobs/
```

Never create an actual job in the chezmoi source repository, never run
`chezmoi add` on a job definition or generated timer, and never copy a private
prompt into tracked documentation. These paths are ignored by the managed
`.chezmoiignore` as a second layer of protection.

Resolve the managed source root with `chezmoi source-path`. Mechanism source is:

```text
<source-root>/dot_local/bin/executable_pi-job
<source-root>/dot_config/private_systemd/private_user/herdr.service
<source-root>/dot_config/private_systemd/private_user/pi-job@.service
<source-root>/.chezmoiscripts/run_onchange_after_35-pi-jobs.sh.tmpl
```

Modify those files only when the user asks to change the shared mechanism.

## Job definition

A normal `job.json` is:

```json
{
  "calendar": "Mon..Fri 08:00",
  "cwd": "/absolute/path/to/project",
  "topology": "tab",
  "workspaceLabel": "Scheduled",
  "tabLabel": "short-name",
  "herdrSession": "default",
  "timeoutMs": 21600000,
  "randomizedDelaySec": "0",
  "accuracySec": "1min",
  "approveProject": false,
  "piArgs": [
    "--provider", "openai-codex-personal",
    "--model", "gpt-5.6-sol",
    "--thinking", "high"
  ]
}
```

Fields:

- `calendar`: required systemd calendar expression.
- `cwd`: required existing absolute working directory.
- `topology`: optional, but only `tab` is accepted.
- `workspaceLabel`: optional, but only `Scheduled` is accepted.
- `tabLabel`: short display name, at most 16 characters. Runs append `MM-DD`.
- `herdrSession`: optional, but only `default` is accepted.
- `timeoutMs`: wait timeout, integer at least 60000; default is six hours. A
  timeout does not kill the Pi process left in Herdr.
- `randomizedDelaySec`: optional systemd time span; default `0`.
- `accuracySec`: optional systemd time span; default `1min`.
- `approveProject`: pass Pi `--approve`. Use only for a directory whose
  project-local resources the user intends to trust non-interactively.
- `piArgs`: optional string array of Pi startup arguments such as `--model`,
  `--thinking`, `--tools`, or `--name`.

The entire `prompt.md` is submitted literally. No shell expansion or prompt
interpolation occurs. Tell Pi to obtain dynamic facts such as the date, Git
state, CI results, or release versions with its tools.

## Create a job

Before creating anything, obtain or confirm:

1. A valid name matching `[a-z][a-z0-9_-]{0,39}`.
2. The calendar schedule and timezone expectations.
3. The absolute working directory.
4. The complete recurring prompt and desired output.
5. Whether the task is read-only or may modify files.
6. Whether project-local Pi resources should be approved.
7. The exact provider/profile, model, thinking level, and any tool restrictions.

For a modifying task, explicitly discuss checkout safety. Do not create a
worktree automatically. Ask whether the user wants the job to operate directly
in the given checkout or in a dedicated persistent worktree. Read-only jobs can
normally use an active checkout; modifying jobs can collide with interactive
edits, branches, locks, tests, or builds.

Then:

```bash
pi-job init <name>
```

Edit the generated private `job.json` and `prompt.md` directly. Keep routing set
to `default` / `Scheduled` / `tab`. Keep `tabLabel` compact. Pin provider,
model, and thinking level explicitly in `piArgs`; do not rely on an interactive
Pi session's current selection or fallback model. Validate and enable it with:

```bash
pi-job install <name>
```

Report the timer's next occurrence from the command output. Do not immediately
run the new job unless the user asks for a test run.

## Prompt guidance

Make unattended prompts bounded and explicit. Include as applicable:

- what to inspect or change;
- whether file edits, commits, pushes, issue updates, or network actions are
  allowed;
- commands or checks that define success;
- what to do when the repository is dirty;
- what to do when information is ambiguous;
- a prohibition on destructive actions not explicitly intended;
- the desired final summary.

Use `piArgs` tool restrictions for least privilege when practical. Tasks that
need interactive login, a graphical session, transient shell environment, an
SSH agent, or privileged approval may fail when run at boot. Do not place
secrets in prompts or timer units.

## Inspect and operate jobs

List definitions and timers:

```bash
pi-job list
```

Inspect one job by reading its private files and its generated timer. Inspect
service logs with:

```bash
journalctl --user -u 'pi-job@<name>.service'
```

Run immediately only when requested:

```bash
pi-job run <name>
```

The runner takes a non-blocking per-job lock. If an earlier service invocation
still holds it, the occurrence is skipped. A persistent timer runs once after a
missed occurrence when the machine and user manager return; it does not replay
every missed interval.

## Update, disable, and remove

To change a job, edit its private files and rerun:

```bash
pi-job install <name>
```

To disable scheduling while retaining the definition and prompt:

```bash
pi-job uninstall <name>
```

`uninstall` removes the generated timer but deliberately retains the private job
directory. Delete that directory only when the user explicitly asks to discard
the job's definition and prompt. Show the exact directory before destructive
removal.

Normal Pi lifecycle notifications flow through the existing Moshi hook. Do not
add separate notification configuration unless the user asks for it.
