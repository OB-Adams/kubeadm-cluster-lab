# shellcheck shell=bash
# Session logging helper. Source it from the repository root (bash or zsh):
#
#   source scripts/run.sh milestone-1-node-prep
#   run ansible-playbook playbooks/node-prep.yml
#
# Every command and its output is appended to logs/<timestamp>-<name>.log
# with a timestamp and exit code, so the log lines up with screenshots.

LOG_DIR="${LOG_DIR:-logs}"
mkdir -p "$LOG_DIR"
SESSION_LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-${1:-session}.log"
export SESSION_LOG

run() {
  local rc
  printf '\n[%s] $ %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$SESSION_LOG"
  "$@" 2>&1 | tee -a "$SESSION_LOG"
  # Read the pipeline status before any other command resets it:
  # PIPESTATUS[0] in bash, pipestatus[1] in zsh.
  # shellcheck disable=SC2154
  rc=${PIPESTATUS[0]:-${pipestatus[1]}}
  printf '[%s] exit=%s\n' "$(date '+%H:%M:%S')" "$rc" | tee -a "$SESSION_LOG"
  return "$rc"
}

note() {
  printf '\n[%s] # %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$SESSION_LOG"
}

echo "Logging to $SESSION_LOG"
