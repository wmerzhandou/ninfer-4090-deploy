#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
install_dir="$repo_root"
enable=0
watchdog=0

while (($#)); do
  case "$1" in
    --install-dir) install_dir="${2:?--install-dir requires a value}"; shift 2 ;;
    --enable) enable=1; shift ;;
    --watchdog) watchdog=1; shift ;;
    -h|--help)
      printf 'Usage: install-systemd.sh [--install-dir DIR] [--enable] [--watchdog]\n'
      printf '  --enable    enable and start 8003/8004/8005 user units\n'
      printf '  --watchdog  also enable the health watchdog unit\n'
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

install_dir="$(cd -- "$install_dir" && pwd)"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p -- "$unit_dir"

render() {
  local source="$1" target="$2"
  sed "s|__INSTALL_DIR__|$install_dir|g" "$source" > "$target"
}

render "$repo_root/systemd/ninfer@.service" "$unit_dir/ninfer@.service"
render "$repo_root/systemd/ninfer-health-watchdog.service" \
  "$unit_dir/ninfer-health-watchdog.service"

systemctl --user daemon-reload
printf 'Installed user units in %s\n' "$unit_dir"
printf 'Edit config/8003.env, config/8004.env, and config/8005.env before starting.\n'

if (( enable )); then
  systemctl --user enable --now ninfer-8003.service ninfer-8004.service ninfer-8005.service
fi
if (( watchdog )); then
  systemctl --user enable --now ninfer-health-watchdog.service
fi
