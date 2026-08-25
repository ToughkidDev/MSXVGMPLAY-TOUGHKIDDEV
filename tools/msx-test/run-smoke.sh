#!/usr/bin/env bash
set -euo pipefail

kit_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
config="$kit_dir/config.local.sh"

if [[ ! -f "$config" ]]; then
  echo "Create tools/msx-test/config.local.sh from config.example.sh first." >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$config"
: "${MSX_TEST_OPENMSX:?MSX_TEST_OPENMSX is required}"
: "${MSX_TEST_MACHINE:?MSX_TEST_MACHINE is required}"
: "${MSX_TEST_COMMAND:?MSX_TEST_COMMAND is required}"

if declare -p MSX_TEST_OPENMSX_ARGS >/dev/null 2>&1; then
  openmsx_args=("${MSX_TEST_OPENMSX_ARGS[@]}")
else
  openmsx_args=()
fi

mkdir -p "$kit_dir/artifacts"
MSX_TEST_COMMAND="$MSX_TEST_COMMAND" \
MSX_TEST_BOOT_SECONDS="${MSX_TEST_BOOT_SECONDS:-130}" \
MSX_TEST_RUN_SECONDS="${MSX_TEST_RUN_SECONDS:-240}" \
MSX_TEST_ARTIFACT_DIR="$kit_dir/artifacts" \
  "$MSX_TEST_OPENMSX" -machine "$MSX_TEST_MACHINE" "${openmsx_args[@]}" -script "$kit_dir/smoke.tcl"
