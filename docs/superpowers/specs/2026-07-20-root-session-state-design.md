# Root runner state isolation

## Goal

Keep `claude+` and `codex+` elevated while reusing the invoking user's current
login. A root session must never write to the user's live home directory.

## Design

Each launcher will:

1. Resolve the invoking user and CLI as it does today.
2. Create a mode-`700` temporary home below `/var/root`.
3. Copy the tool's user state into that temporary home before launch:
   - `claude+`: `~/.claude` and `~/.claude.json`
   - `codex+`: `~/.codex`
4. Launch the CLI as root with `HOME` set to the temporary home.
5. Remove the temporary home when the CLI exits.

The copied state includes the existing login, so the root session does not
require another login. Any state the elevated CLI writes remains private to
root and is discarded at session end.

## Error handling and security

- A missing optional state path is skipped; the CLI retains its normal login
  error if no usable credentials exist.
- A temporary-home or copy failure aborts before the CLI starts.
- Stale homes after a forced kill remain under `/var/root`, never in the
  invoking user's home.
- No new dependency or background cleanup service is introduced.

## Verification

Add a shell test with fake `claude` and `codex` binaries. It will assert that
each launcher receives copied state from the invoking user while its `HOME`
points to a root-owned temporary directory, not the invoking user's home.
