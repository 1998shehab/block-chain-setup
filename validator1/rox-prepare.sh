#!/usr/bin/env bash
set -euo pipefail
source /etc/rox-validator.env

# sanity
for b in solana-keygen solana-genesis solana-validator solana-faucet; do
  [[ -x "$SOLANA_BIN/$b" ]] || { echo "Missing $SOLANA_BIN/$b"; exit 1; }
done
for k in "$IDENTITY" "$VOTE" "$STAKE" "$WITHDRAWER" "$FAUCET" ; do
  [[ -f "$k" ]] || { echo "Missing keypair: $k"; exit 1; }
done

[[ -f "$PRIMORDIAL" ]] || { echo "Missing primordial accounts file: $PRIMORDIAL"; exit 1; }

mkdir -p "$LEDGER"

if [[ "${WIPE_LEDGER:-0}" == "1" ]]; then
  echo "WIPE_LEDGER=1 → wiping $LEDGER"
  rm -rf "$LEDGER"; mkdir -p "$LEDGER"
fi

# build genesis once
if [[ ! -f "$LEDGER/genesis.bin" ]]; then
  echo "==> Building genesis..."
  IDPUB=$("$SOLANA_BIN/solana-keygen" pubkey "$IDENTITY")
  VOTEPUB=$("$SOLANA_BIN/solana-keygen" pubkey "$VOTE")
  STAKEPUB=$("$SOLANA_BIN/solana-keygen" pubkey "$STAKE")
  FAUCETPUB=$("$SOLANA_BIN/solana-keygen" pubkey "$FAUCET")
  "$SOLANA_BIN/solana-genesis" \
    --cluster-type development \
    --hashes-per-tick auto \
    --bootstrap-validator "$IDPUB" "$VOTEPUB" "$STAKEPUB" \
    --bootstrap-validator-lamports "$BOOTSTRAP_LAMPORTS" \
    --bootstrap-validator-stake-lamports "$BOOTSTRAP_STAKE_LAMPORTS" \
    --faucet-pubkey "$FAUCETPUB" \
    --faucet-lamports "$FAUCET_LAMPORTS" \
    --primordial-accounts-file "$PRIMORDIAL" \
    --inflation none \
    --ledger "$LEDGER"
else
  echo "==> Reusing existing genesis at $LEDGER/genesis.bin"
fi