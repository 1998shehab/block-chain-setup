#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Paths
# -------------------------------------------------------------------
LEDGER="./rox-ledger"
SECRETS="./secrets"
IDENTITY="$SECRETS/validator-identity.json"
VOTE="$SECRETS/validator-vote.json"
STAKE="$SECRETS/validator-stake.json"
WITHDRAWER="$SECRETS/withdrawer.json"

SOLANA_BIN="$(pwd)/bin"
for b in solana solana-validator solana-keygen; do
  [[ -x "$SOLANA_BIN/$b" ]] || { echo "Missing $SOLANA_BIN/$b"; exit 1; }
done

# -------------------------------------------------------------------
# Network (public)
# -------------------------------------------------------------------
V1_IP="91.99.236.35"
PUBLIC_IP="91.99.225.119"
RPC_PORT="8899"
GOSSIP_PORT="8001"

mkdir -p "$LEDGER"

# point CLI to validator1
"$SOLANA_BIN/solana" config set --url "http://$V1_IP:$RPC_PORT" >/dev/null
"$SOLANA_BIN/solana" config set --keypair "$IDENTITY" >/dev/null

# ensure vote account exists
VOTE_PUB=$("$SOLANA_BIN/solana-keygen" pubkey "$VOTE")
if ! "$SOLANA_BIN/solana" vote-account "$VOTE_PUB" >/dev/null 2>&1; then
  echo "==> Creating vote account on v1 RPC..."
  "$SOLANA_BIN/solana" create-vote-account \
    "$VOTE" \
    "$IDENTITY" \
    "$("$SOLANA_BIN/solana-keygen" pubkey "$WITHDRAWER")" \
    --commission 8 
fi

GENESIS=$("$SOLANA_BIN/solana" --url "http://$V1_IP:$RPC_PORT" genesis-hash)
echo "==> Using genesis: $GENESIS"

# start validator2
echo "==> Starting validator2..."
exec "$SOLANA_BIN/solana-validator" \
  --identity "$IDENTITY" \
  --vote-account "$VOTE" \
  --ledger "$LEDGER" \
  --entrypoint "$V1_IP:$GOSSIP_PORT" \
  --expected-genesis-hash "$GENESIS" \
  --gossip-host "$PUBLIC_IP" \
  --gossip-port "$GOSSIP_PORT" \
  --rpc-bind-address 0.0.0.0 \
  --rpc-port "$RPC_PORT" \
  --public-rpc-address "$PUBLIC_IP:$RPC_PORT" \
  --full-rpc-api \
  --no-os-network-limits-test \
  --limit-ledger-size \
  > validator2.log 2>&1