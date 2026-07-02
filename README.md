# SudoClaude

Run [Claude Code](https://claude.com/claude-code) or Codex with **root privileges**, from any user account, with a single command: `claude+` or `codex+`.

By default Claude Code refuses to run `--dangerously-skip-permissions` as root/sudo:

```
--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons
```

SudoClaude wraps the CLI in small launchers that:

- **Self-elevates** — run `claude+` or `codex+` as a normal user and it re-execs itself under `sudo` for you (run `sudo claude+` or `sudo codex+` and it just proceeds).
- **Finds your real CLI binary** even though root's `PATH` usually doesn't include it.
- **Sets `IS_SANDBOX=1` for Claude Code**, the environment flag Claude Code checks to permit `--dangerously-skip-permissions` under root.
- **Reuses your existing login** by pointing `HOME` at the invoking user's home directory, so you don't have to re-authenticate as root.

> ⚠️ **Read this before using.** This deliberately runs agentic CLIs as root. Claude Code also runs with `--dangerously-skip-permissions`, which removes an additional safety guard. These sessions can execute commands with **full administrative access and fewer/no confirmation prompts**. Only use this on a machine you own, ideally a disposable VM or container, and only if you understand the risk. See [Security notes](#security-notes).

## Requirements

- Linux (or macOS) with `bash` and `sudo`
- `sudo` privileges for your user
- Claude Code installed for your user — `npm install -g @anthropic-ai/claude-code` (or the official installer). Verify with `claude --version`.
- Codex installed for your user. Verify with `codex --version`.

## Install

```bash
git clone https://github.com/<your-username>/SudoClaude.git
cd SudoClaude
sudo cp claude+ /usr/local/bin/claude+
sudo cp codex+ /usr/local/bin/codex+
sudo chmod 755 /usr/local/bin/claude+
sudo chmod 755 /usr/local/bin/codex+
```

Or as a one-liner from a clone:

```bash
sudo install -m 755 claude+ /usr/local/bin/claude+
sudo install -m 755 codex+ /usr/local/bin/codex+
```

Verify the install:

```bash
grep -n IS_SANDBOX /usr/local/bin/claude+   # should print the IS_SANDBOX=1 line
codex+ --version
```

## Usage

```bash
claude+                 # launch Claude Code as root in the current directory
claude+ --version       # pass any claude arguments straight through
sudo claude+            # same thing, if you're already elevating manually

codex+                  # launch Codex as root in the current directory
codex+ --version        # pass any codex arguments straight through
sudo codex+             # same thing, if you're already elevating manually
```

`claude+` forwards all arguments to `claude`, and `codex+` forwards all arguments to `codex`.

## Uninstall

```bash
sudo rm -f /usr/local/bin/claude+
sudo rm -f /usr/local/bin/codex+
```

## Security notes

- **This is intentionally dangerous.** Agent root guards exist so an agent can't run destructive commands as root without oversight. SudoClaude bypasses that for Claude Code and intentionally runs Codex under `sudo`. Treat every session as if it has full `root` on your box — because it does.
- **File ownership:** because Claude runs as root, any files it creates (including under `~/.claude`) are owned by `root`. If plain `claude` later complains about permissions, fix it with:
  ```bash
  sudo chown -R "$USER:$USER" ~/.claude
  ```
  For Codex, the same applies to `~/.codex`:
  ```bash
  sudo chown -R "$USER:$USER" ~/.codex
  ```
- **Prefer isolation:** run this inside a container or throwaway VM rather than your primary workstation.
- **If you migrated from `claude-code-root-runner`:** that tool created a `claude-temp` user with *passwordless sudo*. SudoClaude does not use it. Remove the leftover privilege‑escalation path:
  ```bash
  sudo rm -f /etc/sudoers.d/claude-temp
  sudo userdel -r claude-temp
  ```

## How it works

Each launcher is one small `bash` script ([`claude+`](./claude+) and [`codex+`](./codex+)). In short:

1. If not root, `exec sudo "$0" "$@"` to elevate.
2. Resolve the invoking user (`SUDO_USER`) and their home directory.
3. Locate the real CLI binary via `PATH` or common install locations.
4. For Claude: `exec env HOME="$RUN_HOME" IS_SANDBOX=1 claude --dangerously-skip-permissions "$@"`.
5. For Codex: `exec env HOME="$RUN_HOME" codex "$@"`.

## Credits

Inspired by [gagarinyury/claude-code-root-runner](https://github.com/gagarinyury/claude-code-root-runner). SudoClaude replaces its temporary‑user + `su` approach (which broke with `su: Authentication failure` when not launched as root) with direct root execution via the `IS_SANDBOX` flag.

## License

[MIT](./LICENSE)
