#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

port="${NINFER_PORT:-8003}"
force=0
while (($#)); do
  case "$1" in
    --port) port="${2:?--port requires a value}"; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help)
      printf 'Usage: stop-ninfer.sh [--port PORT] [--force]\n'
      printf 'Stops a manually started instance tracked by .run/PORT/serve.pid.\n'
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

state_dir="${NINFER_STATE_DIR:-$repo_root/.run/$port}"
pid_file="$state_dir/serve.pid"

if [[ ! -f "$pid_file" ]]; then
  printf 'No PID file for port %s (%s).\n' "$port" "$pid_file" >&2
  printf 'If this instance is managed by systemd, use: systemctl --user stop ninfer-%s.service\n' "$port" >&2
  exit 1
fi

pid="$(<"$pid_file")"
if ! [[ "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
  printf 'Process %s is not running; removing stale PID file.\n' "$pid"
  rm -f -- "$pid_file" "$state_dir/profile"
  exit 0
fi

command_line="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
if [[ "$command_line" != *"ninfer-serve"* || "$command_line" != *"--port $port"* ]]; then
  printf 'Refusing to stop PID %s: command line does not look like port %s.\n' "$pid" "$port" >&2
  exit 1
fi

printf 'Stopping port %s (pid %s)...\n' "$port" "$pid"
kill "$pid"
for _ in $(seq 1 "${NINFER_STOP_TIMEOUT:-120}"); do
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f -- "$pid_file" "$state_dir/profile"
    printf 'Stopped.\n'
    exit 0
  fi
  sleep 1
done

if (( force )); then
  printf 'SIGTERM timed out; sending SIGKILL.\n' >&2
  kill -9 "$pid" 2>/dev/null || true
  rm -f -- "$pid_file" "$state_dir/profile"
  exit 0
fi

printf 'Timed out waiting for PID %s; use --force only if you accept an unclean stop.\n' "$pid" >&2
exit 1
