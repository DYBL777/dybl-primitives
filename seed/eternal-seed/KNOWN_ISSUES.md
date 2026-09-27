# KNOWN_ISSUES: EternalSeed

Limits of the reference itself. What a particular host does with the rule, and that host's own
limits, are in the host's repository.

**The hosts write their own line of the rule, and it is checked through copies.** The games state
the rule in a line of their own rather than calling these functions. `test/HostConformance.t.sol`
fuzzes a copy of each game's line, taken from a named version, against the reference: Lettery
Perpetual, Lettery TF and BullsEthCRE match it exactly. A copy does not follow the game, so a
game that changes its line needs its copy updated before the check means anything.

**SeedTogether does not yet match the reference on rounding.** It rounds its players' share down,
so rounding dust stays in its pot; the reference rounds the seed down and sends the dust to
prizes. Its seed is the reference's or exactly one unit more, and the conformance test pins that
gap. Both conserve the pool. SeedTogether is still in development.

**The library does not validate its inputs.** It is a pure maths reference. Formulation A reverts
on an inverted ordering (payoutBps above maxPayoutBps) through checked arithmetic; Formulation B
clamps a seedBps at or above 10,000 to "the whole pool seeds". A maxPayoutBps above 10,000 with the
ordering intact is silent in most cases and returns values that mean nothing; the exact condition
under which it is surfaced is in the PARAMETER CONSTRAINT section of the source. A host validates
every rate at deployment.

**The projection is linear.** projectedSeedContribution() treats the pot as constant across the
horizon. It under-estimates when the pot is growing and over-estimates when it is shrinking, so it
is for dashboards and calibration, not solvency decisions.

**Coverage.** 25 tests. 14 check the functions' documented claims, 11 of them fuzzed at 2,000 runs;
seven deliberate breaks to the library each fail at least one of them. 6 run a stand-in game over
ten years of weekly draws on flat income. 5 check the games' own lines. Not audited. Not deployed.
