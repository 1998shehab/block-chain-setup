# Blockchain Production Infrastructure Documentation

## Overview

This document describes the production-grade blockchain infrastructure, including validator nodes, RPC/archive nodes, and storage architecture. The setup is designed for high availability, performance, and fault tolerance.

---

## Infrastructure Summary

### Validators
- 4 Validator Servers (Hetzner AX42)
  - RAM: 64 GB
  - CPU: 8-core / 16-thread
  - Storage: 2 × 512 GB SSD
  - Role: Voting validators with private RPC

### RPC / Archive
- 1 Archive Server
  - Total Storage: 160 TB
  - Role: Non-voting RPC + archive node

---

## Validator Roles

- Validator 1: Bootstrap, Faucet, Genesis, Private RPC
- Validator 2: Private RPC, Voting
- Validator 3: Private RPC, Voting
- Validator 4: Private RPC, Voting
- Archive Node: Non-voting RPC + Archive

---

## Build & Setup Steps

### Validator 1 (Bootstrap / Genesis / Faucet)

1. Clone the rox-chain repository
2. Build binaries and copy `target/release/solana*` to `/bin`
3. Create validator secret key files (`*.json`)
4. Create `validator.env`
5. Create `rox-prepare.sh` to generate genesis and ledger if not exists
6. Create faucet service
7. Create validator systemd service

---

### Validator 2 (Private RPC)

1. Copy binaries from Validator 1 to `/bin`
2. Create secret key files (`*.json`)
3. Create `validator.env`
4. Create `join.sh`
5. Create validator systemd service
6. Create vote and stake accounts

---

### Validator 3 (Private RPC)

1. Copy binaries from Validator 1 to `/bin`
2. Create secret key files (`*.json`)
3. Create `validator.env`
4. Create `join.sh`
5. Create validator systemd service
6. Create vote and stake accounts

---

### Validator 4

Same setup as Validator 2 and Validator 3.

---

## RPC / Archive Node (Non-Voting)

1. Copy binaries from Validator 1 to `/bin`
2. Create secret key files (`*.json`)
3. Create rox archive systemd service
4. Create `rox-archive.env`

---

## Archive Server Storage & ZFS Configuration

### Storage Architecture

This server uses a tiered storage architecture optimized for Solana workloads.

---

### System Disks (NVMe)

Two NVMe disks are configured with mdadm RAID1 for:

- `/` (root filesystem)
- `/boot`
- `swap`

This ensures OS stability and redundancy independent of ZFS.

---

### Solana Accounts Database

- Remaining NVMe partition (p4) on each disk
- ZFS mirror pool named `accounts`
- Mounted at: `/mnt/solana-accounts`
- Optimized for low latency and high IOPS (random read/write workloads)

---

### Solana Ledger & Snapshots

- Eight SATA disks combined into a ZFS RAIDZ2 pool named `ledger`
- Mounted at: `/mnt/solana-ledger`

Snapshots:
- Dataset: `ledger/snapshots`
- Mounted at: `/mnt/solana-snapshots`

Optimized for high-throughput sequential I/O and large files.  
RAIDZ2 allows up to two disk failures without data loss.

---

## ZFS Tuning

- `ashift=12` for 4K sector alignment
- Compression enabled (`lz4`)
- `atime` disabled
- Record size and cache policies tuned per dataset:
  - Accounts DB (latency-sensitive)
  - Ledger & archives (throughput-oriented)

---

## Health & Reliability

- All ZFS pools are ONLINE
- Regular scrubs complete with zero errors
- Provides high performance, redundancy, and reliability suitable for production Solana validator and archive nodes
