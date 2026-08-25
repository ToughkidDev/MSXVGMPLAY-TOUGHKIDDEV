#!/usr/bin/env bash
set -euo pipefail

kit_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$kit_dir/../.." && pwd)
config="$kit_dir/config.local.sh"

if [[ ! -f "$config" ]]; then
  echo "Create tools/msx-test/config.local.sh from config.example.sh first." >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$config"
: "${MSX_TEST_DISK_IMAGE:?MSX_TEST_DISK_IMAGE is required}"
: "${MSX_TEST_INSTALL_DESTINATION:?MSX_TEST_INSTALL_DESTINATION is required}"

make -C "$project_dir" all
mcopy -o -i "${MSX_TEST_DISK_IMAGE}@@512" \
  "$project_dir/bin/vgmplay.com" "$MSX_TEST_INSTALL_DESTINATION"
