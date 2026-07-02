# SudoClaude

Run [Claude Code](https://claude.com/claude-code) with **root privileges**, from any user account, with a single command: `claude+`.

By default Claude Code refuses to run `--dangerously-skip-permissions` as root/sudo:

```
--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons
```

SudoClaude wraps the CLI in a small launcher that:

- **Self-elevates** — run `claude+` as a normal user and it re-execs itself under `sudo` for you (run `sudo claude+` and it just proceeds).
- **Finds your real `claude` binary** even though root's `PATH` usually doesn't include it.
- **Sets `IS_SANDBOX=1`**, the environment flag Claude Code checks to permit `--dangerously-skip-permissions` under root.
- **Reuses your existing login** by pointing `HOME` at the invoking user's home directory, so you don't have to re-authenticate as root.

> ⚠️ **Read this before using.** This deliberately removes a safety guard. Running Claude Code as root with `--dangerously-skip-permissions` means it can execute commands with **full administrative access and no confirmation prompts**. Only use it on a machine you own, ideally a disposable VM or container, and only if you understand the risk. See [Security notes](#security-notes).

## Requirements

- Linux (or macOS) with `bash` and `sudo`
- `sudo` privileges for your user
- Claude Code installed for your user — `npm install -g @anthropic-ai/claude-code` (or the official installer). Verify with `claude --version`.

## Install

```bash
git clone https://github.com/<your-username>/SudoClaude.git
cd SudoClaude
sudo cp claude+ /usr/local/bin/claude+
sudo chmod 755 /usr/local/bin/claude+
```

Or as a one-liner from a clone:

```bash
sudo install -m 755 claude+ /usr/local/bin/claude+
```

Verify the install:

```bash
grep -n IS_SANDBOX /usr/local/bin/claude+   # should print the IS_SANDBOX=1 line
```

## Usage

```bash
claude+                 # launch Claude Code as root in the current directory
claude+ --version       # pass any claude arguments straight through
sudo claude+            # same thing, if you're already elevating manually
```

`claude+` forwards all arguments to `claude`, so anything you'd pass to Claude Code works.

## Uninstall

```bash
sudo rm -f /usr/local/bin/claude+
```

## Security notes

- **This is intentionally dangerous.** Claude Code's root guard exists so an agent can't run destructive commands as root without oversight. SudoClaude disables that guard. Treat every session as if it has full `root` on your box — because it does.
- **File ownership:** because Claude runs as root, any files it creates (including under `~/.claude`) are owned by `root`. If plain `claude` later complains about permissions, fix it with:
  ```bash
  sudo chown -R "$USER:$USER" ~/.claude
  ```
- **Prefer isolation:** run this inside a container or throwaway VM rather than your primary workstation.
- **If you migrated from `claude-code-root-runner`:** that tool created a `claude-temp` user with *passwordless sudo*. SudoClaude does not use it. Remove the leftover privilege‑escalation path:
  ```bash
  sudo rm -f /etc/sudoers.d/claude-temp
  sudo userdel -r claude-temp
  ```

## How it works

The entire launcher is one small `bash` script ([`claude+`](./claude+)). In short:

1. If not root, `exec sudo "$0" "$@"` to elevate.
2. Resolve the invoking user (`SUDO_USER`) and their home directory.
3. Locate the `claude` binary via `PATH` or common install locations.
4. `exec env HOME="$RUN_HOME" IS_SANDBOX=1 claude --dangerously-skip-permissions "$@"`.

## Credits

Inspired by [gagarinyury/claude-code-root-runner](https://github.com/gagarinyury/claude-code-root-runner). SudoClaude replaces its temporary‑user + `su` approach (which broke with `su: Authentication failure` when not launched as root) with direct root execution via the `IS_SANDBOX` flag.

## License

[MIT](./LICENSE)
