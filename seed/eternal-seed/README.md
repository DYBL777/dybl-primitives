# EternalSeed

Protect it, grow it, pace it.

The reference for the seed rule behind every game in this suite: how much of a game's pot is
kept back, or comes back, each draw, so the next draw does not start from zero. The seed is the
pot itself under that rule, not a reserve held beside it.

**Pre-testnet. Not deployed, not audited.** The design and the maths are the author's; the
Solidity was written with AI assistance under that direction. What is unproven or carried as a
known limit is in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## What it answers

Two ways of keeping money back:

    FLOOR  a share of the pot is kept out of reach while the season runs
           maxDistributable(pot, payoutBps, maxPayoutBps)
           seedFloor(pot, payoutBps, maxPayoutBps)

    FLOW   a share of every draw's prize pool comes back to the pot
           seedReturn(weeklyPool, seedBps)
           distributable(weeklyPool, seedBps)

`projectedSeedContribution()` is an estimate for dashboards, not for solvency decisions.

## Where it is used

Retention across, how the season ends down:

|                | Floor             | Flow                        |
|----------------|-------------------|-----------------------------|
| **Compound**   | the original idea | Lettery Perpetual           |
| **Port**       | open              | specified, not built        |
| **Spend-down** | open              | SeedTogether                |
| **Return**     | open              | Lettery TF, BullsEthCRE     |

What each draw pays is a separate question, answered by the sizing solvers in
[../../sizing](../../sizing).

## The stand-in game

`test/StandInGame.sol` is the smallest game that holds a pot under either rule: no tickets, no
winners, just income, yield and a payout. `test/StandIn.t.sol` runs it for ten years of weekly
draws on flat income and checks that a held pot pays more than its income once built, that a
seed builds a bigger pot at the cost of paying less in the first year, that a held pot keeps
paying through a year with no income, and that Floor and Flow grow alike at the same effective
rate. Run with `-vv` to see the figures.

## Build and test

    forge install foundry-rs/forge-std@v1.16.2
    forge test
