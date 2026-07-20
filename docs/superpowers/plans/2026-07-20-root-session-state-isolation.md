# Root Session State Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Keep SudoClaude’s elevated launchers logged in without allowing root to write into the invoking user’s home directory.

**Architecture:** Each launcher creates a private temporary home below root’s actual home, copies the user’s relevant CLI state into it, runs the CLI with that temporary home, then removes it on exit. The launchers remain independent Bash scripts.

**Tech Stack:** Bash, \`sudo\`, \`mktemp\`, \`cp\`.

## Global Constraints

- Support macOS (\`dscl\`) and Linux (\`getent\`).
- Preserve \`claude+\`’s \`IS_SANDBOX=1\` and \`--dangerously-skip-permissions\`.
- Never pass the invoking user’s home as \`HOME\` to a root process.
- Keep copied credentials and state below root’s home; add no dependency or daemon.

---

### Task 1: Add a launcher-state regression test

**Files:**
- Create: \`tests/test-launchers.sh\`

**Interfaces:**
- Consumes: executable \`claude+\` and \`codex+\` scripts.
- Produces: a zero-exit test proving each child sees copied state at a temporary, non-user \`HOME\`, and the home is removed when the child exits.

- [ ] **Step 1: Write the failing test**

Create \`tests/test-launchers.sh\`:

\`\`\`bash
#!/bin/bash
set -euo pipefail

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
TEST_BIN="$TEST_ROOT/bin"
mkdir -p "$TEST_BIN"

cat > "$TEST_BIN/id" <<'EOF'
#!/bin/sh
test "$1" = "-u"
printf '0\n'
EOF

cat > "$TEST_BIN/getent" <<'EOF'
#!/bin/sh
case "$2" in
  tester) printf 'tester:x:1000:1000::%s:/bin/sh\n' "$TEST_USER_HOME" ;;
  root) printf 'root:x:0:0::%s:/bin/sh\n' "$TEST_ROOT_HOME" ;;
  *) exit 1 ;;
esac
EOF

cat > "$TEST_BIN/mktemp" <<'EOF'
#!/bin/sh
/bin/mkdir -p "$TEST_SESSION_HOME"
/bin/chmod 700 "$TEST_SESSION_HOME"
printf '%s\n' "$TEST_SESSION_HOME"
EOF

cat > "$TEST_BIN/claude" <<'EOF'
#!/bin/sh
test "$HOME" != "$TEST_USER_HOME"
test -f "$HOME/.claude/login-marker"
test -f "$HOME/.claude.json"
printf '%s\n' "$HOME" > "$TEST_RESULT"
EOF

cat > "$TEST_BIN/codex" <<'EOF'
#!/bin/sh
test "$HOME" != "$TEST_USER_HOME"
test -f "$HOME/.codex/login-marker"
printf '%s\n' "$HOME" > "$TEST_RESULT"
EOF
chmod 755 "$TEST_BIN"/*

check_launcher() {
  local launcher="$1" state_dir="$2"
  local user_home="$TEST_ROOT/$state_dir-user"
  local root_home="$TEST_ROOT/$state_dir-root"
  local session_home="$TEST_ROOT/$state_dir-session"
  local result="$TEST_ROOT/$state_dir-result"

  mkdir -p "$user_home/$state_dir"
  printf 'logged-in\n' > "$user_home/$state_dir/login-marker"
  if [ "$state_dir" = ".claude" ]; then
    printf '{}\n' > "$user_home/.claude.json"
  fi

  PATH="$TEST_BIN:$PATH" SUDO_USER=tester TEST_USER_HOME="$user_home" \
    TEST_ROOT_HOME="$root_home" TEST_SESSION_HOME="$session_home" \
    TEST_RESULT="$result" "$launcher" --version

  test "$(cat "$result")" = "$session_home"
  test ! -e "$session_home"
}

check_launcher "$(dirname "$0")/../claude+" .claude
check_launcher "$(dirname "$0")/../codex+" .codex
printf 'launcher_state_isolation=pass\n'
\`\`\`

- [ ] **Step 2: Run the test to verify it fails**

Run: \`bash tests/test-launchers.sh\`

Expected: FAIL because current launchers give the fake CLI the invoking user’s \`HOME\`.

- [ ] **Step 3: Commit the regression test**

\`\`\`bash
git add tests/test-launchers.sh
git commit -m "test: cover launcher state isolation"
\`\`\`

### Task 2: Isolate root state in both launchers

**Files:**
- Modify: \`claude+\`
- Modify: \`codex+\`

**Interfaces:**
- Consumes: \`SUDO_USER\`, the user’s state paths, and the platform account database.
- Produces: root-run CLI processes with a private temporary \`HOME\` preloaded with user login state.

- [ ] **Step 1: Add root-home lookup and temporary state setup**

In each launcher, retain the existing \`RUN_HOME\` lookup for CLI discovery. Before the final CLI command, resolve root’s home using the same \`getent\`/macOS \`dscl\` fallback, then add:

\`\`\`bash
ROOT_HOME=""
if command -v getent >/dev/null 2>&1; then
    ROOT_HOME="$(getent passwd root | cut -d: -f6 || true)"
fi
if [ -z "$ROOT_HOME" ] && command -v dscl >/dev/null 2>&1; then
    ROOT_HOME="$(dscl . -read /Users/root NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
fi
[ -n "$ROOT_HOME" ] || ROOT_HOME="/root"

ROOT_STATE_HOME="$(mktemp -d "$ROOT_HOME/.sudoclaude.XXXXXX")"
chmod 700 "$ROOT_STATE_HOME"
trap 'rm -rf "$ROOT_STATE_HOME"' EXIT
\`\`\`

- [ ] **Step 2: Copy the required state and invoke Claude**

In \`claude+\`, copy both paths only when they exist:

\`\`\`bash
if [ -e "$RUN_HOME/.claude" ]; then
    cp -R "$RUN_HOME/.claude" "$ROOT_STATE_HOME/"
fi
if [ -e "$RUN_HOME/.claude.json" ]; then
    cp -R "$RUN_HOME/.claude.json" "$ROOT_STATE_HOME/"
fi

env HOME="$ROOT_STATE_HOME" IS_SANDBOX=1 "$CLAUDE_PATH" --dangerously-skip-permissions "$@"
\`\`\`

Replace the old \`exec env HOME="$RUN_HOME" ...\` command. Do not use \`exec\`, because the exit trap must remove temporary state.

- [ ] **Step 3: Copy the required state and invoke Codex**

In \`codex+\`, copy Codex state only when it exists:

\`\`\`bash
if [ -e "$RUN_HOME/.codex" ]; then
    cp -R "$RUN_HOME/.codex" "$ROOT_STATE_HOME/"
fi

env HOME="$ROOT_STATE_HOME" "$CODEX_PATH" "$@"
\`\`\`

Replace the old \`exec env HOME="$RUN_HOME" ...\` command.

- [ ] **Step 4: Run the test and syntax checks**

Run: \`bash tests/test-launchers.sh && bash -n claude+ && bash -n codex+\`

Expected: \`launcher_state_isolation=pass\` and zero exit status.

- [ ] **Step 5: Commit the launcher repair**

\`\`\`bash
git add claude+ codex+
git commit -m "fix: isolate root launcher state"
\`\`\`

### Task 3: Document the state boundary

**Files:**
- Modify: \`README.md\`

**Interfaces:**
- Consumes: the documented launcher behavior.
- Produces: accurate guidance for login reuse, root-created project files, and interrupted sessions.

- [ ] **Step 1: Replace the shared-home claim**

State in the overview and “How it works” that each root run uses a private temporary home seeded from the invoking user’s existing Claude/Codex state. Explicitly say this preserves login while preventing root from modifying the live user home.

- [ ] **Step 2: Correct ownership guidance**

Keep the warning that files created in the project working directory are root-owned. Remove the instructions to repair \`~/.claude\` or \`~/.codex\` with \`chown\`; launcher state no longer writes there. Note that an interrupted session can leave only root-owned temporary state below root’s home.

- [ ] **Step 3: Run final verification**

Run: \`bash tests/test-launchers.sh && bash -n claude+ && bash -n codex+ && git diff --check\`

Expected: \`launcher_state_isolation=pass\`, zero syntax errors, and no whitespace errors.

- [ ] **Step 4: Commit the documentation**

\`\`\`bash
git add README.md
git commit -m "docs: explain isolated root launcher state"
\`\`\`

