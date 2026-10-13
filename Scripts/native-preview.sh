#!/bin/bash
set -euo pipefail
# Runs only on an ephemeral CI runner; never writes a person's notes.
# Usage: native-preview.sh <Mac Scraps.app> <Simulator Scraps.app> [output]
script_directory="$(cd "$(dirname "$0")" && pwd)"
python3 "$script_directory/seed-preview.py" --preview \
  "${1:-build.noindex/DerivedData/Build/Products/Debug/Scraps.app}" \
  "${2:-build.noindex/DerivedData/Build/Products/Debug-iphonesimulator/Scraps.app}" \
  "${3:-build.noindex/Preview}"
