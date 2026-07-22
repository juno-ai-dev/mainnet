# Juno v30 mainnet upgrade — DRAFT

> **Status:** preparation only. No `juno-1` halt height is scheduled by this document. A height becomes authoritative only after an on-chain software-upgrade proposal passes and `junod query upgrade plan` reports plan `v30`.

Juno mainnet will upgrade from v29 to [`v30.0.0`](https://github.com/CosmosContracts/juno/releases/tag/v30.0.0), using the exact release already applied on `uni-7`.

| Item | Value |
|---|---|
| Chain ID | `juno-1` |
| Current versions observed | `v29.0.0` and `v29.1.0` |
| Target version | `v30.0.0` |
| Upgrade plan name | **`v30`** |
| Upgrade height | **TBD — not scheduled** |
| Approximate UTC halt | **TBD — height is authoritative** |
| Release commit | `c0b3a8d258d52d16e5bc39a75168a99aab9d098e` |
| OCI image | `ghcr.io/cosmoscontracts/juno@sha256:081346b118fd327afb6f688ae6d6c6a430a8ff6260d9cd56e0db06630560c4db` |
| Release manifest | [`v30/release-manifest.json`](v30/release-manifest.json) |

The release tag is annotated and peels to the commit above. The GitHub release currently has no attached binary/checksum assets, so these instructions use the same statically linked binaries already published inside the immutable multi-architecture OCI image. Do not install from a mutable image tag.

## What changes in v30

This is a consensus-breaking SDK and state migration. It:

- upgrades to Cosmos SDK `v0.53.7`, CometBFT `v0.38.23`, wasmd `v0.61.11`, wasmvm `v3.0.4`, and IBC-Go `v10.6.0`;
- adds the `feemarket` and `votingsnapshot` stores;
- deletes the `globalfee`, `crisis`, `params`, `nft`, `feeibc`, and `interchainquery` stores;
- backfills voting-snapshot state from current staking delegations;
- enables the fee market for the staking bond denom (`ujuno`) with minimum base gas price `0.075` and maximum block utilization derived from consensus `block.max_gas`;
- sets the cw-hooks contract failure-removal threshold to `3`.

The same `v30.0.0` commit successfully upgraded `uni-7` under plan `v30` at height `16034000`. That testnet height is historical and must never be used for mainnet.

## Readiness gates

Do not submit or announce a mainnet halt until all of these are evidenced:

- [ ] A recent `juno-1` snapshot replay upgrades from the live v29 baseline to this exact binary on at least two nodes with matching app hashes.
- [ ] The public testnet soak and DAO DAO, CosmWasm, bank, staking, governance, tokenfactory, IBC, PFM, and ibc-hooks post-upgrade checks pass.
- [ ] More than 67% of bonded voting power has acknowledged the exact binary checksum, plan name, fee-floor configuration, backup, and staffed halt window; target more than 80% before proposal submission.
- [ ] A pre-halt snapshot has an immutable URL, height, app hash, checksum, independent mirror, and a clean-host restore rehearsal.
- [ ] Incident ownership, communications, objective stop conditions, and a tested fix-forward path are published.
- [ ] Active IBC state is re-audited immediately before proposal submission, including confirmation that no active async-ICQ channel or unresolved ICS-29 fee state will be silently lost.
- [ ] The halt height is calculated from current block time with enough lead for the five-day voting period and validator preparation.
- [ ] The executable `MsgSoftwareUpgrade` payload is rendered from [`v30/software-upgrade-proposal.json.tmpl`](v30/software-upgrade-proposal.json.tmpl), inspected, signed to a temporary file, simulated, and re-queried without broadcasting before authorization.

## Install the exact release binary

Required tools: `curl`, `jq`, `tar`, and `sha256sum`. The downloader selects linux/amd64 or linux/arm64 from the host architecture, fetches the exact OCI layer by digest, and verifies both layer and binary hashes from the release manifest.

```bash
cd juno-1/v30
./download-junod.sh "$HOME/juno-v30/junod"
"$HOME/juno-v30/junod" version --long
sha256sum "$HOME/juno-v30/junod"
```

Expected binary SHA-256:

| Architecture | SHA-256 |
|---|---|
| linux/amd64 | `f782a5f984aa7880ea30e9d98aad71c99fa047aa894d06a16c1a81c658acdbb7` |
| linux/arm64 | `6db8320d0c338ed7adec72e3ca4fd654fd01f2bdbb665f4814b31c919f167b2d` |

The binary must report:

- version `v30.0.0`;
- commit `c0b3a8d258d52d16e5bc39a75168a99aab9d098e`;
- Go `1.25.2`;
- Cosmos SDK `v0.53.7`;
- CometBFT `v0.38.23`;
- wasmvm `v3.0.4`;
- build tags `netgo,muslc`.

The OCI binaries are statically linked. No host `libwasmvm` replacement is required.

## Before the halt

1. Confirm the on-chain plan rather than trusting this document:

   ```bash
   RPC="https://juno-rpc.publicnode.com:443"
   junod query upgrade plan --node "$RPC" --output json
   ```

   The response must name `v30` and show the approved mainnet height. If it does not, stop.

2. Confirm the existing v29 node is healthy, synced, and signing normally.
3. Preserve the current v29 binary and record its checksum/version.
4. Complete the published snapshot/restore procedure. Handle `priv_validator_state.json` separately and never restore stale signing state onto a validator that may have signed later heights.
5. Set `minimum-gas-prices = "0.075ujuno"` in `app.toml`, or leave it empty so the on-chain fee market sets the floor. Do not retain a lower non-empty value.
6. Stage v30 without replacing the running v29 binary.

## Stage with Cosmovisor

The directory must match the on-chain plan name exactly: `v30`.

```bash
export DAEMON_HOME="${DAEMON_HOME:-$HOME/.juno}"
install -d "$DAEMON_HOME/cosmovisor/upgrades/v30/bin"
install -m 0755 "$HOME/juno-v30/junod" \
  "$DAEMON_HOME/cosmovisor/upgrades/v30/bin/junod"

"$DAEMON_HOME/cosmovisor/upgrades/v30/bin/junod" version --long
sha256sum "$DAEMON_HOME/cosmovisor/upgrades/v30/bin/junod"
```

Confirm the version, commit, and architecture-specific checksum above before the halt.

## Manual upgrade

If Cosmovisor is not used, wait for the approved halt. Do not replace the running binary early.

```bash
sudo systemctl stop junod
install -m 0755 "$(command -v junod)" "$HOME/junod-v29-backup"
install -m 0755 "$HOME/juno-v30/junod" "$HOME/go/bin/junod"
"$HOME/go/bin/junod" version --long
sha256sum "$HOME/go/bin/junod"
sudo systemctl start junod
journalctl -u junod -f --no-hostname
```

Adapt service user and paths to the operator's deployment.

## Halt execution

At T-60 minutes:

- confirm the governance proposal passed and `query upgrade plan` returns exactly `v30` at the approved height;
- confirm more than 67% voting power is ready;
- confirm snapshot checksums, two independent RPCs, and incident coordination;
- pause nonessential relayers and transaction automation.

At the halt:

1. Confirm the v29 binary stopped because of the scheduled upgrade—not a consensus or infrastructure failure.
2. Verify `$DAEMON_HOME/data/upgrade-info.json` contains plan name `v30` and the approved height.
3. Start v30 and preserve migration logs.
4. Watch for store-loader, voting-snapshot backfill, wasmvm, IBC, and fee-market errors.
5. Never delete state or run `unsafe-reset-all` in response to a migration panic.
6. Confirm at least 67% upgraded voting power and two post-upgrade blocks before resuming automation.

## Post-upgrade verification

From at least two independent RPC/REST providers:

```bash
RPC="https://juno-rpc.publicnode.com:443"
REST="https://juno-rest.publicnode.com"
UPGRADE_HEIGHT="<APPROVED_MAINNET_HEIGHT>"
DELEGATOR="<EXISTING_JUNO_ADDRESS>"

junod status --node "$RPC"
junod query upgrade applied v30 --node "$RPC" --output json
junod query upgrade module-versions --node "$RPC" --output json
junod query feemarket params --node "$RPC" --output json
junod query feemarket gas-price ujuno --node "$RPC" --output json
junod query cw-hooks params --node "$RPC" --output json

curl -fsS "$REST/juno/feemarket/v1/params" | jq
curl -fsS "$REST/juno/feemarket/v1/state" | jq
curl -fsS "$REST/juno/feemarket/v1/gas_price/ujuno" | jq
curl -fsS "$REST/juno/votingsnapshot/v1/params" | jq
curl -fsS "$REST/juno/votingsnapshot/v1/voting_power/$DELEGATOR/$UPGRADE_HEIGHT" | jq
curl -fsS "$REST/juno/votingsnapshot/v1/total_voting_power/$UPGRADE_HEIGHT" | jq
```

Acceptance criteria:

- plan `v30` is applied at the approved height and blocks continue;
- independent providers agree on height and app hash;
- post-upgrade commit signatures represent at least 67% bonded voting power;
- fee market is enabled for `ujuno`, minimum base gas price is `0.075`, and maximum block utilization is `100000000`;
- cw-hooks failure-removal threshold is `3`;
- voting-snapshot returns sensible backfilled power for an existing delegator and total power;
- existing DAO DAO and CosmWasm contracts can be queried and safely exercised;
- controlled bank, staking, governance, tokenfactory, IBC, PFM, and ibc-hooks transactions succeed with the v30 client;
- no store-loader, migration, wasmvm ABI, app-hash, or consensus errors appear.

## Failure policy

Before the first post-upgrade block commits, preserve logs and coordinate either a corrected binary or the pre-agreed network-wide restore procedure.

After any post-upgrade block commits, individual validators must not roll back independently. Coordinate a deterministic fix-forward release or an explicitly agreed network-wide recovery. Restoring stale validator signing state can cause double-signing.
