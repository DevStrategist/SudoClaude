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
