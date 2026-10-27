#!/usr/bin/env bash
set -euo pipefail
galaxy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$galaxy_dir/runtime/bin:/run/current-system/sw/bin:$PATH"
exec python3 "$galaxy_dir/bar.py" "$@"
