#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHUNKS="${1:-$ROOT/workflows/chunks}"
OUT="${2:-$ROOT/workflows/minimaxH3SEEDHUNTERLatent_v21.json}"

mkdir -p "$(dirname "$OUT")"
mapfile -t FILES < <(find "$CHUNKS" -maxdepth 1 -type f -name 'part-*.b64' | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "ERROR: no workflow chunks found in $CHUNKS" >&2
    exit 1
fi

TMP="${OUT}.tmp"
trap 'rm -f "$TMP"' EXIT
cat "${FILES[@]}" | tr -d '\r\n' | base64 -d | gzip -dc > "$TMP"
python3 -m json.tool "$TMP" >/dev/null
mv "$TMP" "$OUT"
trap - EXIT

echo "Workflow ready: $OUT"
wc -c "$OUT"
