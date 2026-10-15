# XeloraCoin

Token suite with M-of-N owner control. The admin functions were behind
`onlyOwner`; they now require agreement from several owners. Notes below on
the approach and the trade-offs, since the threshold choices aren't all
self-explanatory.

## Background

Everything privileged on these contracts hung off one key. `setUpgradeAgent`
is the bad one: set the agent to a contract you control and every holder who
calls `upgrade()` burns their balance and receives whatever your agent decides
to give them, which can be nothing. The same key could also drain the vault via
`reclaimToken`, pause transfers indefinitely, or sweep ether out with
`reclaimEther`.

A quorum doesn't prevent key compromise, it just raises the number of keys an
attacker needs. That's the whole goal here.

## Multiownable

`contracts/xelora/ownership/Multiownable.sol`. Owner list plus a quorum count,
three modifiers (`onlyAnyOwner`, `onlyManyOwners`, `onlyAllOwners`).

There's no separate propose/confirm interface. An owner calls the function
normally; the modifier hashes `msg.data` together with `ownersGeneration` and
records a vote against that hash. The call that brings the count up to the
threshold is the one that actually runs the function body. Everyone before that
pays gas for a vote and nothing else happens.

Because the calldata is in the hash, owners are voting on exact arguments.
Two owners calling `reclaimEther` with different `_to` addresses have voted for
two different operations and neither executes — you'd see two entries in
`allOperations` with one vote each. Worth knowing when you're wondering why
nothing happened.

Votes live in a bitmask (`votesMaskByOperation`), so an owner can't double-vote
and the owner set is capped at 256. Any change to the owner set bumps
`ownersGeneration`, which invalidates every pending operation. `cancelPending`
withdraws a single vote.

One wrinkle: `insideCallSender`/`insideCallCount` let a confirmed operation call
another privileged function on the same contract without a second round of
votes. Without it, any internal call between two guarded functions would
deadlock.

## Thresholds

| Function | Owners needed |
| --- | --- |
| `setUpgradeAgent` | all |
| `lock`, `unlock` | quorum |
| `unpause` | quorum |
| `reclaimEther`, `reclaimToken` | quorum |
| `transferOwnershipWithHowMany` | quorum |
| `pause` | any one |
| `setAllocation` | any one |
| `transferFor` | any one |

`setUpgradeAgent` is `onlyAllOwners` rather than a quorum. It's irreversible
once holders start migrating, it's the largest possible loss, and there is no
scenario where it has to happen in the next ten minutes. Unanimity costs
nothing here.

`pause` is deliberately a single owner and `unpause` is a quorum. Pausing only
removes capability, and if you need three signatures to hit the brake you'll
hit it after the funds are gone. Unpausing has to be harder, otherwise a stolen
key just reverses the pause that was pulled because of the theft.

`setAllocation` is a single owner for practical reasons — a distribution list
can be hundreds of addresses and nobody is going to collect a quorum per entry.
The check moved to `lock()` instead, which reverts unless `tokensAllocated`
equals the `tokensToBeAllocated` fixed in the constructor, and unless the
vault's own balance actually covers that. A wrong or malicious allocation fails there, and nothing is claimable until
lock and unlock have both happened.

`transferFor` is a single owner because it can only move an allocation to the
beneficiary it's already assigned to. It's a convenience for users who can't
call `claim()` themselves.

Owner rotation is a quorum, not unanimity. Making it unanimous means one lost
key permanently freezes the contract, including the ability to replace the key
that was lost.

## Other changes

`Claimable`, `CanReclaimToken` and `PausableToken` are gone. Each one inherits
`Ownable`, so keeping them would have left `owner` and `onlyOwner` live
alongside the quorum — two access-control systems on one contract, and the
weaker one still works.

That does cost the two-step ownership transfer `Claimable` provided. Partial
mitigation: the new owner array is inside the hashed calldata, so a quorum of
owners would all have to submit the same wrong address for a bad transfer to go
through. Not identical protection, but not nothing.

`reclaimEther(address _to)` and `reclaimToken(ERC20Basic _token, address _to)`
take an explicit destination now. There's no single `owner` left to default to,
and making the destination part of the voted-on calldata is better anyway.

`TokenVault.canReclaimToken` returns false for the token being distributed.
This was exploitable before the multiownable work as well — `reclaimToken`
moves a whole balance, and the vault's balance belongs to the beneficiaries.
Other tokens sent to the vault by mistake can still be recovered.

## Known gaps

- Keys held by one person are one key regardless of what the contract enforces.
  Operational problem, not solvable here.
- Deployer is the sole owner until `transferOwnershipWithHowMany` runs. That
  call should be the next transaction after deployment, before the contract
  holds anything.
- Votes don't expire. A vote cast months ago still counts if the operation is
  still pending. Rotating owners clears them; so does `cancelPending`.
- No timelock. A quorum executes immediately. A delay on `setUpgradeAgent`
  specifically is the obvious next addition, so holders can exit before a
  migration begins.
- 256 owner maximum, from the bitmask.

## Build

```bash
npm install
npm run build
```

Note on the build: the original sources didn't compile. No build config, and
the imports referenced a `../zeppelin/` directory that wasn't present. I moved
everything under `contracts/`, added Hardhat, and pinned `openzeppelin-solidity`
to 1.10.0, which is the last version targeting Solidity 0.4.23. Compiler and
`evmVersion` are pinned in `hardhat.config.js`.

## Deployment

Deploy, then call `transferOwnershipWithHowMany(owners, quorum)` immediately.
Verify `ownersCount()`, `howManyOwnersDecide()` and `isOwner()` for each key
before funding anything.
