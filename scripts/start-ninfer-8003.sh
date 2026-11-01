#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: start-ninfer-8003.sh pure|fast [--restart] [--print-command]

  pure           A16 prefill + MTP3, no prompt lookup
  fast           A16 prefill + MTP3 + K15 prompt lookup (min-match 12)
  --restart      Stop the managed process for the configured port before starting
  --print-command  Print the resolved command without starting the service
EOF
}

profile="${1:-}"
case "$profile" in
  pure|fast) shift ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

restart=0
print_command=0
for argument in "$@"; do
  case "$argument" in
    --restart) restart=1 ;;
    --print-command) print_command=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

server="${NINFER_SERVER:-$repo_root/build-sergiuszm/apps/ninfer-serve}"
model="${NINFER_MODEL:-$repo_root/models/qwen3_8_27b.ninfer}"
port="${NINFER_PORT:-8003}"
visible_devices="${NINFER_VISIBLE_DEVICES:-1}"
max_concurrency="${NINFER_MAX_CONCURRENCY:-4}"
kv_capacity="${NINFER_KV_CAPACITY:-auto}"
max_pending_requests="${NINFER_MAX_PENDING_REQUESTS:-16}"
pending_timeout_ms="${NINFER_PENDING_TIMEOUT_MS:-600000}"
api_key="${NINFER_API_KEY:-change-me}"
state_dir="${NINFER_STATE_DIR:-$repo_root/.run/serve-$port}"
pid_file="$state_dir/serve.pid"
profile_file="$state_dir/profile"
log_file="$state_dir/serve.log"

if [[ ! -x "$server" ]]; then
  printf 'Missing executable: %s\n' "$server" >&2
  exit 1
fi
if [[ ! -f "$model" ]]; then
  printf 'Missing model: %s\n' "$model" >&2
  exit 1
fi

args=(
  "$model"
  --host 0.0.0.0 --port "$port" --api-key "$api_key"
  --model-id qwen3.8-27b --max-context 262144 --kv-capacity "$kv_capacity"
  --max-concurrency "$max_concurrency" --max-pending-requests "$max_pending_requests"
  --pending-timeout-ms "$pending_timeout_ms" --prefill-chunk 2048 --kv-dtype rk4v4-e8
  --prefill-activations a16 --spec mtp --draft-tokens 3 --lm-head-draft
)
if [[ "$profile" == fast ]]; then
  args+=(--prompt-lookup-tokens 15 --prompt-lookup-min-match 12)
fi
args+=(--device 0)

if (( print_command )); then
  printf 'CUDA_VISIBLE_DEVICES=%q ' "$visible_devices"
  printf '%q ' "$server" "${args[@]}"
  printf '\n'
  exit 0
fi

mkdir -p -- "$state_dir"

managed_pid=''
if [[ -f "$pid_file" ]]; then
  managed_pid="$(<"$pid_file")"
  if [[ "$managed_pid" =~ ^[0-9]+$ ]] && kill -0 "$managed_pid" 2>/dev/null; then
    command_line="$(tr '\0' ' ' < "/proc/$managed_pid/cmdline")"
    if [[ "$command_line" != *"$server"* || "$command_line" != *"--port $port"* ]]; then
      printf 'Refusing PID file pointing to an unexpected process: %s\n' "$managed_pid" >&2
      exit 1
    fi
    if (( ! restart )); then
      running_profile="$(cat "$profile_file" 2>/dev/null || printf 'unknown')"
      printf 'Port %s is already running (pid %s, profile %s); use --restart to switch.\n' \
        "$port" "$managed_pid" "$running_profile" >&2
      exit 1
    fi
    kill "$managed_pid"
    for _ in $(seq 1 60); do
      kill -0 "$managed_pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$managed_pid" 2>/dev/null; then
      printf 'Timed out stopping pid %s\n' "$managed_pid" >&2
      exit 1
    fi
  else
    rm -f -- "$pid_file"
  fi
fi

if ss -ltn "( sport = :$port )" | tail -n +2 | grep -q .; then
  printf 'Port %s is already in use by an unmanaged process; refusing to start.\n' "$port" >&2
  exit 1
fi

printf '\n[%s] starting profile=%s\n' "$(date -Is)" "$profile" >> "$log_file"
CUDA_VISIBLE_DEVICES="$visible_devices" setsid nohup \
  "$server" "${args[@]}" >> "$log_file" 2>&1 < /dev/null &
pid=$!
printf '%s\n' "$pid" > "$pid_file"
printf '%s\n' "$profile" > "$profile_file"

healthy=0
for _ in $(seq 1 180); do
  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'Service exited during startup. Recent log:\n' >&2
    tail -n 40 -- "$log_file" >&2
    rm -f -- "$pid_file" "$profile_file"
    exit 1
  fi
  if curl -fsS --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 1
done

if (( ! healthy )); then
  printf 'Service did not become healthy within 180 seconds; stopping pid %s.\n' "$pid" >&2
  kill "$pid" 2>/dev/null || true
  rm -f -- "$pid_file" "$profile_file"
  exit 1
fi

lookup='off'
[[ "$profile" == fast ]] && lookup='K15 min-match 12'
printf 'profile=%s\n' "$profile"
printf 'lookup=%s\n' "$lookup"
printf 'max_concurrency=%s\n' "$max_concurrency"
printf 'kv_capacity=%s\n' "$kv_capacity"
printf 'max_pending_requests=%s\n' "$max_pending_requests"
printf 'pending_timeout_ms=%s\n' "$pending_timeout_ms"
printf 'base_url=http://127.0.0.1:%s/v1\n' "$port"
printf 'api_key=%s\n' "$api_key"
printf 'model=qwen3.8-27b\n'
printf 'pid=%s\n' "$pid"
printf 'log=%s\n' "$log_file"
