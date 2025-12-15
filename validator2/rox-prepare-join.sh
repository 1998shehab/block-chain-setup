#!/usr/bin/env bash
set -euo pipefail
source /etc/rox-validator.env

# sanity
for b in solana-keygen solana-validator; do
  [[ -x "$SOLANA_BIN/$b" ]] || { echo "Missing $SOLANA_BIN/$b"; exit 1; }
done
for k in "$IDENTITY" "$VOTE" "$STAKE" "$WITHDRAWER"; do
  [[ -f "$k" ]] || { echo "Missing keypair: $k"; exit 1; }
done
: "${ENTRYPOINT:?missing}"
: "${EXPECTED_GENESIS_HASH:?missing}"
: "${KNOWN_VALIDATOR:?missing}"

mkdir -p "$LEDGER"
if [[ "${WIPE_LEDGER:-0}" == "1" ]]; then
  rm -rf "$LEDGER"; mkdir -p "$LEDGER"
fi