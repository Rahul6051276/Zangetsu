#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$repo_root/server/sync/refresh_jwks.sh"
fixtures="$repo_root/test/server/fixtures"

"$script" --validate "$fixtures/jwks_public.json"

if "$script" --validate "$fixtures/jwks_private.json"; then
  printf 'private signing material was accepted\n' >&2
  exit 1
fi

if "$script" --validate "$fixtures/jwks_empty.json"; then
  printf 'an empty key set was accepted\n' >&2
  exit 1
fi
