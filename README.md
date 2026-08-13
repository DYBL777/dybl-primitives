# DYBL primitives

Trust infrastructure for pooled commitment. Small, auditable Solidity libraries extracted
from a working protocol, each verified against the contract it came from.

Licensed under BUSL-1.1. Change Date 24 February 2030, converting to MIT. See LICENSE.

---

## What is here

| Primitive | Version | What it does |
|---|---|---|
| `BreathEngine.sol` | v1.4 | Autonomous forward-projecting distribution rate solver |
| `EternalSeed.sol` | v1.7 | Capital retention: taxonomy and reference implementation |

Both are pure libraries. No state, no storage, no external calls, no dependencies.

## The problem BreathEngine solves

Any protocol that holds capital and owes something later faces the same question every
period: **how much can I pay out now without failing my obligation at maturity?**

Most protocols answer it with a fixed rate chosen at launch, or with governance votes after
the fact. Neither adapts. A fixed rate is either too cautious in good conditions or
insolvent in bad ones, and governance is too slow to be a control loop.

We call this the **Autonomous Distribution Rate Problem**, and to our knowledge no
production protocol answers it autonomously and forward-projecting. `BreathEngine.solve()`
does: given current stock, an obligation floor, periods remaining and an inflow estimate, it
returns the maximum rate that still clears the floor at maturity. Twenty-four iterations of
geometric binary search, every advance verified directly against the projection.

The distinction worth naming: streaming protocols move money at a rate you set. This solves
for the rate.

## The Eternal Seed

A portion of capital retained and compounded rather than paid out. Two formulations, a floor
on the pot (Formulation A) and a fraction of each period's pool (Formulation B), which
compose into a seventeen-variant design space catalogued in the file's own documentation.
`BreathEngine` is variant sixteen: Formulation B flow whose distribution side is
solver-governed.

The functions are one to three lines each. The value is the taxonomy.

## How these were verified

These are extractions, not rewrites, and the extraction is what needed proving.

`BreathEngine` was validated by differential fuzzing against a verbatim replica of the solver
inside `BullsEthCRE`, the protocol it came from: byte-equal across thousands of runs, with
one documented boundary difference at exact equality. That reference contract carries 425
tests and a nine-property invariant campaign covering clean seasons, emergency resets,
dormancy wind-downs and circuit-breaker recovery.

Both libraries have been through repeated audit rounds. Their changelogs record every
finding, including the ones that turned out to be wrong, and including corrections to
earlier corrections. The pattern is worth stating plainly: **across every round, every
finding has been in the prose, never in the arithmetic.** The changelogs are cumulative and
are the honest record, not a highlights reel.

## Using them

```solidity
import {BreathEngine} from "dybl-primitives/src/BreathEngine.sol";

uint256 rate = BreathEngine.solve(
    stock,          // capital held now
    floor,          // what must remain at maturity
    periodsLeft,
    revenueEMA,     // BreathEngine.updateEMA maintains this
    seedBps,        // rollover fraction, 0 if unused
    maxRateBps      // your ceiling
);
```

Read the header of each file before integrating. Both carry porter notes covering the
guards that look removable and are not, the ambiguity of a zero return, and the exact
boundaries of every claim made about them.

Internal libraries inline into the caller and add nothing to deployment beyond the code you
actually use.

## Repository layout

```
src/           the libraries
test/          probe suites and the differential fidelity suite
changelogs/    one cumulative changelog per primitive
docs/          papers and specifications
PROVENANCE.md  where each primitive came from
```

## Status

Pre-audit. Not deployed. No production use is licensed before the Change Date.

Contact: dybl7@proton.me
