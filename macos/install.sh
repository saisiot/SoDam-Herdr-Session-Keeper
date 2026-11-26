#!/bin/sh
set -eu

if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' 'Node.js 22.13 이상이 필요합니다.' >&2
  exit 1
fi
exec node "$(dirname "$0")/install.mjs" "$@"
