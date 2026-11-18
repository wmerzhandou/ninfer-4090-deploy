#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/start-ninfer.sh" \
  --port "${NINFER_PORT:-8004}" \
  --gpu "${NINFER_GPU:-2}" \
  --profile "${NINFER_PROFILE:-fast}" \
  "$@"
