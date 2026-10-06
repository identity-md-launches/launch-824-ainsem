# AINSEM

AINSEM is an immutable ERC-20 with name and symbol `AINSEM`, 18 decimals, and an initial supply of **1,000,000,000 tokens** (`1000000000000000000000000000` base units). Its constructor mints the entire supply to `msg.sender` exactly once.

## Transfer behavior and assumptions

The request specifies a 1% transfer charge but no recipient. This implementation **burns that charge permanently**. For an ordinary transfer of `amount` base units:

- The sender spends `amount`.
- `floor(amount / 100)` is burned, reducing `totalSupply()`.
- The recipient receives `amount - floor(amount / 100)`.

For example, transferring 100 AINSEM delivers 99 AINSEM and burns 1. This applies to both `transfer` and `transferFrom`; allowance is charged for the gross amount. Infinite allowances retain standard OpenZeppelin behavior. Self-transfers also burn 1%, with only the burn lost from the sender's balance. The sender must hold the full requested amount even for a self-transfer.

Rounding is per transfer in base units: amounts below 100 base units burn nothing. Splitting transfers can reduce the aggregate burn through rounding. Zero transfers succeed and emit a `Transfer` event. Zero recipients and zero approval spenders revert. A burn emits `Transfer(sender, address(0), burned)` before the net transfer event. Failed transfers roll back balances, supply, and allowance together.

There are no external mint, voluntary burn, burnFrom, owner, fee setter, exemption setter, pause, blacklist, seizure, upgrade, rescue, or initialization functions. Supply can only decrease after construction. No account can spend another holder's tokens without allowance, including exempt launch infrastructure.

## Required launch exemptions

The protected launch checks require full amounts to reach the distributor, claimants, pool, and requester. Therefore the 1% rule applies to ordinary transfers with these explicit exceptions:

| Condition | Reason |
| --- | --- |
| Caller is the immutable factory | Factory distributions and seeding arrive whole. |
| Caller, sender, or recipient is the immutable PoolManager | Pool settlements and token legs of buys/sells arrive whole. |
| Caller or sender is the current distributor for this launch | Contributor claims arrive whole. |

Sending tokens **to** the factory or distributor alone does not exempt a holder. The PoolManager exemption deliberately covers sales made by an ordinary trader or an approved router. Such pool trades have no AINSEM burn. Other pools and integrations have no automatic exemption and must support fee-on-transfer tokens. Claims themselves are exempt; a claimant's later ordinary transfers are taxed.

The distributor is resolved at transfer time through `factory.distributorOf(uint64 launchNumber)`, because it is registered after token creation. A missing, reverting, over-gas, or malformed lookup is treated as no distributor exemption, allowing ordinary transfers to continue. The lookup uses a 30,000-gas `STATICCALL` and copies at most 32 bytes. The factory and PoolManager exemptions do not depend on that lookup. **Distributor claims must not be executed while the registry is unhealthy**, since they would then be taxed.

## Deployment parameters

Production contract: `src/AINSEM.sol:AINSEM`.

```solidity
constructor(address factory_, address poolManager_, uint64 launchNumber_)
```

| Argument | Launch value | Validation |
| --- | --- | --- |
| `factory_` | `$factory` | Nonzero and equal to constructor `msg.sender`. |
| `poolManager_` | `$poolManager` | Nonzero and different from the factory. |
| `launchNumber_` | `$launchNumber` | Exact registry key, within `uint64`; zero is allowed. |

The factory deploys the token directly, including through CREATE2. All constructor arguments are static ABI types. Encode them in the order above and append `abi.encode(factory, poolManager, launchNumber)` to the compiled creation bytecode. No initialization calls or application contracts are needed. Minting to the constructor caller ensures the factory holds the full launch supply. Deploying through an unrelated helper with the intended factory argument reverts.

The deployment manifest's token entry should use:

```json
{
  "contract": "src/AINSEM.sol:AINSEM",
  "name": "AINSEM",
  "symbol": "AINSEM",
  "decimals": 18,
  "constructorArgs": ["$factory", "$poolManager", "$launchNumber"],
  "totalSupply": "1000000000000000000000000000"
}
```

This is the token entry only, not a complete launch manifest. Chain addresses, paired currency, pool settings, initial price, requester address, and launch economics were not provided. The launch operator must supply and verify them through the network's deployment process. No live chain addresses are assumed and no transactions are broadcast by this project. A standalone EOA can deploy with itself as `factory_`, but its outgoing transfers are then permanently exempt and it has no contributor registry; the intended network deployment uses ProjectFactory.

## Build and verification

With Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins the compiler by version, targets Cancun, enables the optimizer with 200 runs, and uses `bytecode_hash = "none"`. FFI and filesystem cheatcode permissions are not enabled. All imported source dependencies and licenses are in `lib/`; no download or environment variables are needed by the delivered tests. The verifier supplies the compiler offline.

Recorded local results with Foundry 1.8.3 and Solidity 0.8.26: `forge build`, `forge test` (34 passed, 0 failed), and `forge fmt --check` all passed. The stateful invariant completed 8,192 calls with no handler reverts. All vendored source/license checksums passed `sha256sum -c lib/SHA256SUMS`.

The tests cover metadata and constructor validation, burn amounts/events/rounding, zero values and invalid addresses, approvals and revocation, gross-balance/allowance failures and atomicity, self-transfers, full launch distributions and pool token movements, late distributor registration, registry failure and reentrancy attempts, absent privileged selectors, runtime opcode restrictions, and fuzzed transfers over the supply range. A stateful invariant suite runs randomized transfers, approvals, and delegated transfers across ordinary and exempt actors, checking balance conservation and exact cumulative burns. Default fuzzing runs 512 cases per fuzz test; invariants run 128 sequences of depth 64.

The pool tests model the token settlement legs; they do not instantiate Uniswap v4 or execute real swaps. The supplied protected harness depends on the network's factory/pool fixtures and launch manifest environment, so it remains an independent admission check. No tests depend on the temporary `.imd/reads/` inputs or `test/scratch/`.

## Operational responsibilities and review

The launch operator must verify the factory and PoolManager addresses on the chosen Cancun-compatible chain, confirm the factory's distributor getter and launch number, and register the correct distributor before claims. Exemption routing trusts those contracts and the factory's registry entry; changes to that entry change which distributor is exempt. Registry implementations must answer within the lookup gas limit. The constructor checks address shape and deployer identity, not external bytecode correctness. All token configuration is permanent.

Wallets and integrations must show gross debits and net receipts accurately and measure received balances for ordinary transfers. Users should grant only the allowances they need. The broad PoolManager exemption is required for settlement and can also permit transfers routed through that infrastructure without a burn; the token does not enforce a universal economic tax. There is no treasury to collect fees and no token administrator to recover misplaced assets or repair configuration.

Before release, the operator is responsible for the independent protected launch checks, adversarial review, and explorer verification of the deployed bytecode and constructor parameters. The local unit, fuzz, and invariant checks are not an independent security audit. Slither and Mythril are not part of the recorded checks for this assignment.
