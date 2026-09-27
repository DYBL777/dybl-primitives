# BreathEngine

A Solidity library that answers one question each period: given the stock on hand, a floor that
must still be there at maturity, the periods left and the expected income, what is the most that
can safely be paid out now?

**Pre-testnet. Not deployed, not audited.** The design and the maths are the author's; the
Solidity was written with AI assistance under that direction. What is unproven or carried as a
known limit is in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## What it answers

    solve(stock, floor, periods, revPerPeriod, seedBps, maxBreathBps) returns (safeBps)

    safeBps   the highest payout rate, in basis points of the stock, that still leaves at
              least `floor` after `periods`, by a 24-step search checked against a projection

    isInsolvent(...)   true when even paying nothing cannot reach the floor
    sim(...)           the projection the search checks against
    updateEMA(...)     a running average for the income estimate
    potHealth(...)     stock as basis points of the floor

A zero from `solve()` does not by itself mean distress; see KNOWN_ISSUES.md.

## Where it came from

The solver was first built inside BullsEthCRE, a prediction game whose season must end with a
floor still in the pot, and lifted out here. The tests include a replica of that game's solver,
and the two agree except at one documented boundary.

## Build and test

    forge install foundry-rs/forge-std@v1.16.2
    forge test
