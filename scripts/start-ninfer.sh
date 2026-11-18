#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: start-ninfer.sh [options]

Options:
  --port PORT              listening port (or NINFER_PORT)
  --gpu INDEX              physical GPU index (or NINFER_GPU)
  --profile fast|pure|baseline
                           fast: MTP3 + K15 lookup (default)
                           pure: MTP3 only, for byte-exact regression
                           baseline: no speculative decoding, diagnostics only
  --restart                stop the managed process for this port first
  --foreground             exec in the foreground (for systemd)
  --print-command          print the resolved command and exit
  -h, --help               show this help

The server binary and model default to build/apps/ninfer-serve and
models/qwen3_8_27b.ninfer under the repository root. Override them with
NINFER_SERVER and NINFER_MODEL. The API key must be set with NINFER_API_KEY;
the default is only a placeholder and should not be used on a shared network.
EOF
}

port="${NINFER_PORT:-}"
gpu="${NINFER_GPU:-0}"
profile="${NINFER_PROFILE:-fast}"
restart=0
foreground=0
print_command=0

while (($#)); do
  case "$1" in
    --port) port="${2:?--port requires a value}"; shift 2 ;;
    --gpu) gpu="${2:?--gpu requires a value}"; shift 2 ;;
    --profile) profile="${2:?--profile requires a value}"; shift 2 ;;
    --restart) restart=1; shift ;;
    --foreground) foreground=1; shift ;;
    --print-command) print_command=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$port" ]]; then
  printf 'Missing --port (or NINFER_PORT)\n' >&2
  usage
  exit 2
fi
case "$profile" in
  fast|pure|baseline) ;;
  *) printf 'Invalid profile: %s\n' "$profile" >&2; exit 2 ;;
esac
if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
  printf 'Invalid port: %s\n' "$port" >&2
  exit 2
fi
if ! [[ "$gpu" =~ ^[0-9]+$ ]]; then
  printf 'Invalid GPU index: %s\n' "$gpu" >&2
  exit 2
fi
if (( foreground && restart )); then
  printf '--foreground and --restart cannot be combined\n' >&2
  exit 2
fi

server="${NINFER_SERVER:-$repo_root/build/apps/ninfer-serve}"
model="${NINFER_MODEL:-$repo_root/models/qwen3_8_27b.ninfer}"
host="${NINFER_HOST:-0.0.0.0}"
api_key="${NINFER_API_KEY:-change-me}"
model_id="${NINFER_MODEL_ID:-qwen3.8-27b}"
max_context="${NINFER_MAX_CONTEXT:-262144}"
kv_capacity="${NINFER_KV_CAPACITY:-1048576}"
max_concurrency="${NINFER_MAX_CONCURRENCY:-6}"
max_pending_requests="${NINFER_MAX_PENDING_REQUESTS:-16}"
pending_timeout_ms="${NINFER_PENDING_TIMEOUT_MS:-600000}"
max_private_continuations="${NINFER_MAX_PRIVATE_CONTINUATIONS:-32}"
max_shared_prefixes="${NINFER_MAX_SHARED_PREFIXES:-12}"
host_state_slots="${NINFER_HOST_STATE_SLOTS:-16}"
host_kv_mib="${NINFER_HOST_KV_MIB:-16384}"
prefill_chunk="${NINFER_PREFILL_CHUNK:-2048}"
kv_dtype="${NINFER_KV_DTYPE:-rk4v4-e8}"
default_max_tokens="${NINFER_DEFAULT_MAX_TOKENS:-65536}"
prefill_activations="${NINFER_PREFILL_ACTIVATIONS:-a16}"
draft_tokens="${NINFER_DRAFT_TOKENS:-3}"
lookup_tokens="${NINFER_PROMPT_LOOKUP_TOKENS:-15}"
lookup_min_match="${NINFER_PROMPT_LOOKUP_MIN_MATCH:-12}"
vision_max_tokens="${NINFER_VISION_MAX_TOKENS:-8192}"
vision="${NINFER_VISION:-1}"
cuda_graph="${NINFER_CUDA_GRAPH:-0}"
request_log="${NINFER_REQUEST_LOG:-}"
state_dir="${NINFER_STATE_DIR:-$repo_root/.run/$port}"
startup_timeout="${NINFER_STARTUP_TIMEOUT:-300}"
stop_timeout="${NINFER_STOP_TIMEOUT:-120}"
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
if (( max_concurrency < 1 || max_concurrency > 8 )); then
  printf 'NINFER_MAX_CONCURRENCY must be in 1..8 (got %s)\n' "$max_concurrency" >&2
  exit 2
fi
if (( prefill_chunk < 1 || prefill_chunk > 2688 )); then
  printf 'NINFER_PREFILL_CHUNK must be in 1..2688 (got %s)\n' "$prefill_chunk" >&2
  exit 2
fi
if [[ "$kv_capacity" != "auto" ]] && { ! [[ "$kv_capacity" =~ ^[0-9]+$ ]] || (( kv_capacity < max_context )); }; then
  printf 'NINFER_KV_CAPACITY must be auto or >= max-context (got %s)\n' "$kv_capacity" >&2
  exit 2
fi
if [[ "$api_key" == "change-me" ]]; then
  printf 'Warning: NINFER_API_KEY is still the placeholder change-me\n' >&2
fi

args=(
  "$model"
  --host "$host"
  --port "$port"
  --api-key "$api_key"
  --model-id "$model_id"
  --max-context "$max_context"
  --kv-capacity "$kv_capacity"
  --max-concurrency "$max_concurrency"
  --max-pending-requests "$max_pending_requests"
  --pending-timeout-ms "$pending_timeout_ms"
  --max-private-continuations "$max_private_continuations"
  --max-shared-prefixes "$max_shared_prefixes"
  --host-state-slots "$host_state_slots"
  --host-kv-mib "$host_kv_mib"
  --prefill-chunk "$prefill_chunk"
  --kv-dtype "$kv_dtype"
  --default-max-tokens "$default_max_tokens"
  --prefill-activations "$prefill_activations"
)

if [[ "$profile" == "fast" || "$profile" == "pure" ]]; then
  args+=(--spec mtp --draft-tokens "$draft_tokens" --lm-head-draft)
fi
if [[ "$profile" == "fast" ]]; then
  args+=(--prompt-lookup-tokens "$lookup_tokens" --prompt-lookup-min-match "$lookup_min_match")
fi
if [[ "$vision" != "0" ]]; then
  args+=(--vision --vision-max-tokens "$vision_max_tokens")
fi
if [[ "$cuda_graph" != "1" ]]; then
  args+=(--no-cuda-graph)
fi
if [[ -n "$request_log" ]]; then
  args+=(--request-log-jsonl "$request_log")
fi
args+=(--device 0)

if (( print_command )); then
  printf 'CUDA_VISIBLE_DEVICES=%q ' "$gpu"
  printf '%q ' "$server" "${args[@]}"
  printf '\n'
  exit 0
fi

if (( foreground )); then
  exec env CUDA_VISIBLE_DEVICES="$gpu" "$server" "${args[@]}"
fi

stop_managed() {
  local pid="$1"
  local command_line
  command_line="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  if [[ "$command_line" != *"$server"* || "$command_line" != *"--port $port"* ]]; then
    printf 'Refusing PID file pointing to an unexpected process: %s\n' "$pid" >&2
    return 1
  fi
  kill "$pid"
  for _ in $(seq 1 "$stop_timeout"); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 1
  done
  printf 'Timed out stopping pid %s\n' "$pid" >&2
  return 1
}

if [[ -f "$pid_file" ]]; then
  managed_pid="$(<"$pid_file")"
  if [[ "$managed_pid" =~ ^[0-9]+$ ]] && kill -0 "$managed_pid" 2>/dev/null; then
    if (( ! restart )); then
      running_profile="$(cat "$profile_file" 2>/dev/null || printf 'unknown')"
      printf 'Port %s is already running (pid %s, profile %s); use --restart to switch.\n' \
        "$port" "$managed_pid" "$running_profile" >&2
      exit 1
    fi
    stop_managed "$managed_pid"
  fi
  rm -f -- "$pid_file" "$profile_file"
fi

if ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then
  printf 'Port %s is already in use by an unmanaged process; refusing to start.\n' "$port" >&2
  exit 1
fi

mkdir -p -- "$state_dir"
printf '\n[%s] starting profile=%s gpu=%s\n' "$(date -Is)" "$profile" "$gpu" >> "$log_file"
CUDA_VISIBLE_DEVICES="$gpu" setsid nohup \
  "$server" "${args[@]}" >> "$log_file" 2>&1 < /dev/null &
pid=$!
printf '%s\n' "$pid" > "$pid_file"
printf '%s\n' "$profile" > "$profile_file"

healthy=0
for _ in $(seq 1 "$startup_timeout"); do
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
  printf 'Service did not become healthy within %s seconds; stopping pid %s.\n' \
    "$startup_timeout" "$pid" >&2
  kill "$pid" 2>/dev/null || true
  rm -f -- "$pid_file" "$profile_file"
  exit 1
fi

printf 'profile=%s\n' "$profile"
printf 'gpu=%s\n' "$gpu"
printf 'max_concurrency=%s\n' "$max_concurrency"
printf 'kv_capacity=%s\n' "$kv_capacity"
printf 'max_context=%s\n' "$max_context"
printf 'max_pending_requests=%s\n' "$max_pending_requests"
printf 'pending_timeout_ms=%s\n' "$pending_timeout_ms"
printf 'host_kv_mib=%s\n' "$host_kv_mib"
printf 'base_url=http://127.0.0.1:%s/v1\n' "$port"
printf 'model=%s\n' "$model_id"
printf 'pid=%s\n' "$pid"
printf 'log=%s\n' "$log_file"
