# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 token for an IMD custom-token launch on Ethereum (chain id 1).

| Parameter | Value |
|-----------|-------|
| Solidity contract (launch identifier) | `MADToken` (`src/MADToken.sol`) |
| `name()` | `Mutually Assured Destruction` |
| `symbol()` | `MAD` |
| `decimals()` | `18` |
| Total supply | `1,000,000,000 MAD` = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Owner / admin | none |

## Behaviour

- The constructor mints the whole supply once to `msg.sender`. At launch that is the IMD
  `ProjectFactory`, which then pays the supply out (10% to the launch's MerkleDistributor, 80% to
  the single-sided pool, 10% to the requester's `remainderTo` address).
- Transfers, approvals and `transferFrom` follow plain ERC-20 semantics (OpenZeppelin v5.1.0
  `ERC20`). There is no transfer fee, burn-on-transfer, pause, blocklist, freeze, reflection or
  exemption list, so every launch flow (factory to distributor, seed through the PoolManager,
  claims, buys and sells) moves exactly the amount requested.
- No function can mint after the constructor. There is no `owner()`, no `Ownable`, no
  upgradeability, no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` in the runtime code, and the
  contract refuses plain ETH.
- Supply can only shrink by holders sending tokens to an address nobody controls; the contract has
  no `burn` function of its own.

## Assumptions

- The brief asked for a token with a name, symbol and supply, and no transfer rules. None were
  added. Because the token taxes nothing, it does not need the `$factory`, `$poolManager` or
  `$launchNumber` constructor arguments and takes none.
- Nothing in the contract needs an owner, so it does not inherit `Ownable`. There is no address for
  anyone to hold and nothing to transfer after deployment.
- The compiler is pinned to `solc = "0.8.26"` with `bytecode_hash = "none"` and
  `cbor_metadata = false`, so the deployed bytes are reproducible and compared without a metadata
  hash, as the launch requires. `evm_version` is `cancun`.
- No value in this project is a stand-in for something the requester must supply.

## Deployment parameters

The IMD launch deploys the token through its factory from the bytecode as built; nothing here
broadcasts transactions or holds keys. The manifest step (not this repository) writes `launch.json`
after acceptance. Values it will need:

- `token.contract`: `MADToken`
- `token.name`: `Mutually Assured Destruction`
- `token.symbol`: `MAD`
- `token.decimals`: `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`
- Application contracts: none.

For a local or stand-alone deployment, `script/DeployMADToken.s.sol` exposes `deploy()`, which
`new`s the token and is what the tests call directly; `run()` wraps it in a broadcast. Whoever
deploys receives the whole supply.

## After launch

Nothing to configure. The token has no owner-settable values, so there is no setter to call and no
value the owner has to obtain anywhere.

## Operational responsibilities

- **Requester**: receives 10% of the supply at `economics.remainderTo`
  (`0xff3e8d9ba776662ca6ed1420ee366afb436d2684`) and is responsible for that wallet's keys. The
  token itself gives the requester no power over other holders.
- **IMD deployer / launch policy**: deploys the token, opens the IMD-paired Uniswap v4 pool at the
  fee and tick spacing the launch policy sets, seeds it, and forwards the swarm's share to the
  MerkleDistributor. Explorer source verification after deployment belongs to this step.
- **Holders**: self-custody. Tokens sent to a wrong address cannot be recovered by anyone.

## Security notes

Checked against the `eth-security` reference: no external calls, no reentrancy surface, no oracle,
no approvals granted by the contract, no privileged functions, no proxy. The only state-changing
entry points are the standard ERC-20 `transfer`, `approve` and `transferFrom`, each guarded by
OpenZeppelin's balance, allowance and zero-address checks and each emitting its event. Tests
passing is not an audit; an independent adversarial review before release remains good practice.
Static analysers (Slither, Mythril) were not available in this environment and did not run.

## Repository layout

```
foundry.toml            compiler pins and build settings
remappings.txt          forge-std and @openzeppelin/contracts remappings
src/MADToken.sol        the token
test/MADToken.t.sol     unit and fuzz tests
script/DeployMADToken.s.sol  reviewable deployment helper
lib/forge-std           forge-std v1.9.7 (vendored as plain files, MIT/Apache-2.0)
lib/openzeppelin-contracts   OpenZeppelin Contracts v5.1.0, ERC20 subset only (MIT)
```

## Build and test

```
forge build
forge test
forge fmt --check
```

Tests read no environment variables and run in any order and in parallel. Fuzz tests were run with
`FOUNDRY_FUZZ_SEED=0x5d54c8ad855e1670651356314f2a093e217e80f348efca0c8fdea141ca330f4d`, the seed the
verifier uses.
