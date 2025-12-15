[Unit]
Description=ROX Validator (join existing cluster)
After=network-online.target
Wants=network-online.target

[Service]
User=sol
Group=sol
WorkingDirectory=/home/sol/rox
EnvironmentFile=/etc/rox-validator.env
ExecStartPre=/usr/local/bin/rox-prepare-join.sh
ExecStart=/home/sol/rox/bin/solana-validator \
  --no-port-check \
  --identity ${IDENTITY} \
  --vote-account ${VOTE} \
  --ledger ${LEDGER} \
  --gossip-host ${PUBLIC_IP} \
  --entrypoint ${ENTRYPOINT} \
  --expected-genesis-hash ${EXPECTED_GENESIS_HASH} \
  --known-validator ${KNOWN_VALIDATOR} \
  --gossip-port ${GOSSIP_PORT} \
  --rpc-bind-address ${RPC_HOST} \
  --rpc-port ${RPC_PORT} \
  --public-rpc-address ${PUBLIC_IP}:${RPC_PORT} \
  --full-rpc-api \
  --limit-ledger-size ${LEDGER_SHREDS_LIMIT} \
  --full-snapshot-interval-slots 200 \
  --incremental-snapshot-interval-slots 100
Restart=always
RestartSec=2
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target