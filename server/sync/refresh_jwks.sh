#!/usr/bin/env bash
set -euo pipefail

validate_jwks() {
  jq -e '
    type == "object" and
    (.keys | type == "array" and length > 0) and
    all(.keys[];
      type == "object" and
      (.kid | type == "string" and length > 0) and
      (has("d") | not) and (has("p") | not) and (has("q") | not) and
      (has("dp") | not) and (has("dq") | not) and (has("qi") | not) and
      (has("k") | not) and
      ((.kty == "EC" and .crv == "P-256" and
        (.x | type == "string" and length > 0) and
        (.y | type == "string" and length > 0) and
        (.alg == null or .alg == "ES256")) or
       (.kty == "RSA" and
        (.n | type == "string" and length > 0) and
        (.e | type == "string" and length > 0) and
        (.alg == null or .alg == "RS256")))
    )
  ' "$1" > /dev/null
}

if [[ ${1:-} == --validate && $# == 2 ]]; then
  validate_jwks "$2"
  exit
fi
if [[ $# != 0 ]]; then
  printf 'usage: %s [--validate jwks.json]\n' "$0" >&2
  exit 2
fi

source_url=https://eogwzrlfoercfwcfwlmv.supabase.co/auth/v1/.well-known/jwks.json
destination=/etc/zangetsu-sync/jwks.json
temp_file=$(mktemp "${destination}.tmp.XXXXXX")
trap 'rm -f "$temp_file"' EXIT

curl --fail --silent --show-error --location --proto '=https' \
  --max-time 20 --retry 2 --output "$temp_file" "$source_url"
validate_jwks "$temp_file"

if [[ ! -f $destination ]] || ! cmp --silent "$temp_file" "$destination"; then
  chown root:sync_authenticator "$temp_file"
  chmod 0640 "$temp_file"
  mv -f "$temp_file" "$destination"
fi
# Re-signal even if the file is unchanged: a previous reload may have failed.
systemctl kill --signal=SIGUSR2 zangetsu-sync-stage.service
