#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
build_dir="${NINFER_BUILD_DIR:-$repo_root/build}"
jobs="${NINFER_BUILD_JOBS:-4}"
cmake_bin="${CMAKE_BIN:-cmake}"
generator="${NINFER_CMAKE_GENERATOR:-Ninja}"

if ! command -v "$cmake_bin" >/dev/null 2>&1; then
  printf 'cmake not found; set CMAKE_BIN or install CMake 3.28+\n' >&2
  exit 1
fi

cmake_args=(
  -S "$repo_root"
  -B "$build_dir"
  -G "$generator"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_CUDA_ARCHITECTURES=89
  -DNINFER_BUILD_APPS=ON
  -DBUILD_TESTING=OFF
  -DNINFER_BUILD_BENCHMARKS=OFF
)
[[ -n "${CC:-}" ]] && cmake_args+=(-DCMAKE_C_COMPILER="$CC")
[[ -n "${CXX:-}" ]] && cmake_args+=(-DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_CUDA_HOST_COMPILER="$CXX")
[[ -n "${CUDACXX:-}" ]] && cmake_args+=(-DCMAKE_CUDA_COMPILER="$CUDACXX")

printf 'Configuring in %s\n' "$build_dir"
"$cmake_bin" "${cmake_args[@]}"
printf 'Building ninfer-serve with %s jobs\n' "$jobs"
"$cmake_bin" --build "$build_dir" --target ninfer-serve --parallel "$jobs"

printf '\nBinary: %s\n' "$build_dir/apps/ninfer-serve"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$build_dir/apps/ninfer-serve"
fi
