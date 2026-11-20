#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-/www/.toolchains/flutter/bin/flutter}"
API_BASE="${HG_API_BASE:-https://d1716d.bmikbxhi.cc}"
PORT="${WEB_PORT:-43125}"

# shellcheck source=/dev/null
source "$ROOT/tool/_project_tmp_env.sh"

exec "$FLUTTER_BIN" run \
  -d web-server \
  --web-hostname 127.0.0.1 \
  --web-port "$PORT" \
  --dart-define="HG_API_BASE=$API_BASE"
