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
FAUCET="$SECRETS/faucet.json"
PRIMORDIAL="$SECRETS/accounts.yaml"     # optional
# Binaries
SOLANA_BIN="$(pwd)/bin"
for b in solana solana-genesis solana-validator solana-faucet solana-keygen; do
  [[ -x "$SOLANA_BIN/$b" ]] || { echo "Missing $SOLANA_BIN/$b"; exit 1; }
done
# -------------------------------------------------------------------
# Network
# -------------------------------------------------------------------
PUBLIC_IP="91.99.236.35"
RPC_HOST="0.0.0.0"
RPC_PORT="8899"
FAUCET_HOST="127.0.0.1"
FAUCET_PORT="9900"
GOSSIP_HOST="$PUBLIC_IP"
GOSSIP_PORT="8001"
RPC_URL="http://127.0.0.1:${RPC_PORT}"
FAUCET_ADDR="${FAUCET_HOST}:${FAUCET_PORT}"
# -------------------------------------------------------------------
# Limits & disk guard
# -------------------------------------------------------------------
MIN_FREE_GB=10
LEDGER_SHREDS_LIMIT=50000000
MAX_LOG_MB=200
MAX_LOG_BACKUPS=5
# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
bytes_to_mb() { awk '{printf "%.0f", $1/1024/1024}'; }
file_mb() { [[ -f "$1" ]] && stat -c%s "$1" | bytes_to_mb || echo 0; }
rotate_log_if_big() {
  local f="$1"; local sz_mb
  sz_mb=$(file_mb "$f")
  if (( sz_mb > MAX_LOG_MB )); then
    local ts; ts=$(date +%F_%H%M%S)
    mv "$f" "${f}.${ts}"
    gzip -9 "${f}.${ts}" || true
    ls -1t "${f}."* 2>/dev/null | tail -n +"$((MAX_LOG_BACKUPS+1))" | xargs -r rm -f
  fi
}
free_gb() { df --output=avail -BG / | tail -1 | tr -dc '0-9'; }
ensure_space_or_cleanup() {
  local free=$(free_gb)
  if (( free < MIN_FREE_GB )); then
    echo "Low disk: ${free}GB free < ${MIN_FREE_GB}GB."
    if [[ "${ALLOW_LEDGER_PURGE:-0}" == "1" ]]; then
      echo "ALLOW_LEDGER_PURGE=1 → purging ledger to reclaim space..."
      rm -rf "$LEDGER" || true
      mkdir -p "$LEDGER"
    else
      echo "Refusing to purge ledger automatically. Free up space or rerun with ALLOW_LEDGER_PURGE=1."
      exit 1
    fi
  fi
}
# -------------------------------------------------------------------
# Stop previous runs
# -------------------------------------------------------------------
pkill -f solana-validator 2>/dev/null || true
pkill -f solana-faucet 2>/dev/null || true
sleep 0.5
# -------------------------------------------------------------------
# Disk-space guard
# -------------------------------------------------------------------
ensure_space_or_cleanup
# -------------------------------------------------------------------
# Fresh ledger (optional wipe)
# -------------------------------------------------------------------
mkdir -p "$LEDGER"
echo "WIPE_LEDGER=${WIPE_LEDGER:-0}"
if [[ "${WIPE_LEDGER:-0}" == "1" ]]; then
  echo "WIPE_LEDGER=1 → wiping $LEDGER"
  rm -rf "$LEDGER"
  mkdir -p "$LEDGER"
else
  echo "Keeping existing ledger (no wipe)"
fi
# -------------------------------------------------------------------
# Bootstrap balances
# -------------------------------------------------------------------
LAMPORTS_PER_SOL=1000000000
BOOTSTRAP_LAMPORTS=$((5000 * LAMPORTS_PER_SOL))
BOOTSTRAP_STAKE_LAMPORTS=$((2000 * LAMPORTS_PER_SOL))
FAUCET_LAMPORTS=$((10000 * LAMPORTS_PER_SOL))
# Sanity: keys exist
for k in "$IDENTITY" "$VOTE" "$STAKE" "$FAUCET"; do
  [[ -f "$k" ]] || { echo "Missing keypair: $k"; exit 1; }
done
# -------------------------------------------------------------------
# Build genesis only if needed
# -------------------------------------------------------------------
if [[ ! -f "$LEDGER/genesis.bin" ]]; then
  echo "==> Building genesis..."
  GEN_ARGS=(
    --cluster-type development
    --hashes-per-tick auto
    --bootstrap-validator "$($SOLANA_BIN/solana-keygen pubkey "$IDENTITY")" \
                          "$($SOLANA_BIN/solana-keygen pubkey "$VOTE")" \
                          "$($SOLANA_BIN/solana-keygen pubkey "$STAKE")"
    --bootstrap-validator-lamports "$BOOTSTRAP_LAMPORTS"
    --bootstrap-validator-stake-lamports "$BOOTSTRAP_STAKE_LAMPORTS"
    --faucet-pubkey "$($SOLANA_BIN/solana-keygen pubkey "$FAUCET")"
    --faucet-lamports "$FAUCET_LAMPORTS"
    --ledger "$LEDGER"
  )
  if [[ -f "$PRIMORDIAL" ]]; then
    echo "   including primordial accounts: $PRIMORDIAL"
    GEN_ARGS+=( --primordial-accounts-file "$PRIMORDIAL" )
  fi
  "$SOLANA_BIN/solana-genesis" "${GEN_ARGS[@]}"
else
  echo "==> Reusing existing genesis at $LEDGER/genesis.bin"
fi
# -------------------------------------------------------------------
# Start faucet
# -------------------------------------------------------------------
echo "==> Starting faucet..."
rotate_log_if_big faucet.log || true
nohup "$SOLANA_BIN/solana-faucet" \
  --keypair "$FAUCET" \
  --host "$FAUCET_HOST" \
  --port "$FAUCET_PORT" \
  > faucet.log 2>&1 &
rm -f ./solana-validator-*.log
# -------------------------------------------------------------------
# Start validator
# -------------------------------------------------------------------
echo "==> Starting validator..."
rotate_log_if_big validator.log || true
RUST_LOG=warn nohup "$SOLANA_BIN/solana-validator" \
  --identity "$IDENTITY" \
  --vote-account "$VOTE" \
  --ledger "$LEDGER" \
  --gossip-host "$GOSSIP_HOST" \
  --gossip-port "$GOSSIP_PORT" \
  --rpc-bind-address "$RPC_HOST" \
  --rpc-port "$RPC_PORT" \
  --public-rpc-address "$PUBLIC_IP:$RPC_PORT" \
  --full-rpc-api \
  --enable-rpc-transaction-history \
  --rpc-faucet-address "$FAUCET_ADDR" \
  --no-wait-for-vote-to-start-leader \
  --limit-ledger-size "$LEDGER_SHREDS_LIMIT" \
  --full-snapshot-interval-slots 2000 \
  --incremental-snapshot-interval-slots 1000 \
  --log validator.log &
# -------------------------------------------------------------------
# Wait for health
# -------------------------------------------------------------------
echo -n "==> Waiting for RPC health "
for i in {1..120}; do
  if curl -s "${RPC_URL}" -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' \
      | grep -q '"ok"'; then
    echo " ✓"
    break
  fi
  echo -n "."
  sleep 0.5
  if [[ $i -eq 120 ]]; then
    echo
    echo "Validator failed to become healthy. See validator.log"
    exit 1
  fi
done
# -------------------------------------------------------------------
# Set CLI default URL
# -------------------------------------------------------------------
"$SOLANA_BIN/solana" config set --url "$RPC_URL" >/dev/null
GENESIS=$("$SOLANA_BIN/solana" genesis-hash)
echo "Genesis Hash: $GENESIS"
# -------------------------------------------------------------------
# Usage message
# -------------------------------------------------------------------
cat <<'USAGE'
✅ Validator1 (bootstrap) is up.
Quick commands:
  airdrop() { ./bin/solana airdrop "$1" "$2" --url http://127.0.0.1:8899; }
  tail -f validator.log
  tail -f faucet.log
  curl -s http://127.0.0.1:8899 -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}'
  ./bin/solana cluster-version
  ./bin/solana leader-schedule | head
  # stop
  pkill -f solana-validator; pkill -f solana-faucet
USAGE