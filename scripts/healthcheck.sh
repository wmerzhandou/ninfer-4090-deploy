#!/usr/bin/env bash
set -euo pipefail

host="${NINFER_HEALTH_HOST:-127.0.0.1}"
ports="${NINFER_PORTS:-8003 8004 8005}"
timeout="${NINFER_HEALTH_TIMEOUT:-5}"

while (($#)); do
  case "$1" in
    --host) host="${2:?--host requires a value}"; shift 2 ;;
    --ports) ports="${2:?--ports requires a value}"; shift 2 ;;
    --timeout) timeout="${2:?--timeout requires a value}"; shift 2 ;;
    -h|--help)
      printf 'Usage: healthcheck.sh [--host HOST] [--ports "8003 8004 8005"] [--timeout SECONDS]\n'
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

failed=0
for port in $ports; do
  if body="$(curl -fsS --max-time "$timeout" "http://$host:$port/health" 2>/dev/null)"; then
    printf 'OK   %s:%s  %s\n' "$host" "$port" "$body"
  else
    printf 'FAIL %s:%s  health endpoint unreachable\n' "$host" "$port"
    failed=1
  fi
done

exit "$failed"
