#!/usr/bin/env bash
set -euo pipefail

ports="${NINFER_WATCH_PORTS:-8003 8004 8005}"
interval="${NINFER_WATCH_INTERVAL:-20}"
threshold="${NINFER_WATCH_THRESHOLD:-3}"
timeout="${NINFER_WATCH_TIMEOUT:-5}"
once=0

while (($#)); do
  case "$1" in
    --once) once=1; shift ;;
    --ports) ports="${2:?--ports requires a value}"; shift 2 ;;
    -h|--help)
      printf 'Usage: health-watchdog.sh [--once] [--ports "8003 8004 8005"]\n'
      printf 'Environment: NINFER_WATCH_INTERVAL, NINFER_WATCH_THRESHOLD, NINFER_WATCH_TIMEOUT\n'
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

declare -A failures=()
for port in $ports; do failures["$port"]=0; done

check_once() {
  local port body
  for port in $ports; do
    if body="$(curl -fsS --max-time "$timeout" "http://127.0.0.1:$port/health" 2>/dev/null)" \
      && [[ "$body" == *'"ok"'* ]]; then
      failures["$port"]=0
      continue
    fi
    failures["$port"]=$(( failures["$port"] + 1 ))
    printf '%s port=%s failures=%s/%s\n' "$(date -Is)" "$port" \
      "${failures[$port]}" "$threshold" >&2
    if (( failures["$port"] >= threshold )); then
      printf '%s restarting ninfer-%s.service\n' "$(date -Is)" "$port" >&2
      if systemctl --user restart "ninfer-$port.service"; then
        failures["$port"]=0
        sleep 60
      else
        printf '%s restart failed for ninfer-%s.service (is the unit installed?)\n' \
          "$(date -Is)" "$port" >&2
      fi
    fi
  done
}

if (( once )); then
  check_once
  exit 0
fi

while true; do
  check_once
  sleep "$interval"
done
