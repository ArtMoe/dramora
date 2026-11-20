#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/www/.toolchains/flutter/bin/flutter}"
API_BASE="${HG_API_BASE:-https://d1716d.bmikbxhi.cc}"

# shellcheck source=/dev/null
source "$ROOT/tool/_project_tmp_env.sh"

exec "$FLUTTER_BIN" build web \
  --release \
  --pwa-strategy=none \
  --no-wasm-dry-run \
  --dart-define="HG_API_BASE=$API_BASE"
