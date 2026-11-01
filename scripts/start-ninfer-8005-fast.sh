#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export NINFER_PORT="${NINFER_PORT:-8005}"
export NINFER_VISIBLE_DEVICES="${NINFER_VISIBLE_DEVICES:-0}"
export NINFER_MAX_CONCURRENCY="${NINFER_MAX_CONCURRENCY:-6}"
export NINFER_KV_CAPACITY="${NINFER_KV_CAPACITY:-1048576}"
exec "$script_dir/start-ninfer-8003-fast.sh" "$@"
