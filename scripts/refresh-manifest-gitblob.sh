#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="SOURCE_MANIFEST_SHA256.txt"
TMP="${OUT}.tmp"
: > "$TMP"
while IFS= read -r -d "" f; do
  [ "$f" = "$OUT" ] && continue
  hash="$(git cat-file blob "HEAD:$f" | sha256sum | awk '{print $1}')"
  printf "%s  %s\n" "$hash" "$f" >> "$TMP"
done < <(git ls-files -z)
mv "$TMP" "$OUT"
echo "manifest_files=$(wc -l < "$OUT" | tr -d ' ')"
sha256sum "$OUT"
