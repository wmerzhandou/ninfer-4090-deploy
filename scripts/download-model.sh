#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

model_dir="${NINFER_MODEL_DIR:-$repo_root/models}"
model="$model_dir/qwen3_8_27b.ninfer"
revision="${NINFER_MODEL_REVISION:-3526913004b1}"
expected_sha256="eec39564993d6e9c7d5e383382a760f093465c9d163ec9a1bd6b80199514bf3e"
endpoint="${HF_ENDPOINT:-https://huggingface.co}"
url="$endpoint/neroued/Qwen3.8-27B-NInfer/resolve/$revision/qwen3_8_27b.ninfer"

mkdir -p -- "$model_dir"
printf 'Downloading Qwen3.8-27B NInfer (revision %s)...\n' "$revision"
printf 'URL: %s\n' "$url"

if ! curl -L -C - --fail --output "$model" "$url"; then
  printf 'Download failed. Re-run to resume; the partial file is kept.\n' >&2
  exit 1
fi

if [[ -z "${NINFER_SKIP_SHA256:-}" ]]; then
  actual_sha256="$(sha256sum -- "$model" | cut -d' ' -f1)"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    printf 'SHA-256 mismatch.\n  expected: %s\n  actual:   %s\n' \
      "$expected_sha256" "$actual_sha256" >&2
    exit 1
  fi
  printf 'SHA-256 verified.\n'
fi

printf 'Model ready: %s\n' "$model"
