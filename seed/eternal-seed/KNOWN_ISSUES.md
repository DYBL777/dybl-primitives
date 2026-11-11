# KNOWN_ISSUES: EternalSeed

Limits of the reference itself. What a particular host does with the rule, and that host's own
limits, are in the host's repository.

**The hosts write their own line of the rule, and it is checked through copies.** The games state
the rule in a line of their own rather than calling these functions. `test/HostConformance.t.sol`
fuzzes a copy of each game's line, taken from a named version, against the reference: Lettery
Perpetual, Lettery TF, BullsEthCRE and SeedTogether match it exactly. A copy does not follow the
game, so a game that changes its line needs its copy updated before the check means anything.

**The library does not validate its inputs.** It is a pure maths reference. Formulation A reverts
on an inverted ordering (payoutBps above maxPayoutBps) through checked arithmetic; Formulation B
clamps a seedBps at or above 10,000 to "the whole pool seeds". A maxPayoutBps above 10,000 with the
ordering intact is silent in most cases and returns values that mean nothing; the exact condition
under which it is surfaced is in the PARAMETER CONSTRAINT section of the source. A host validates
every rate at deployment.

**The projection is linear.** projectedSeedContribution() treats the pot as constant across the
horizon. It under-estimates when the pot is growing and over-estimates when it is shrinking, so it
is for dashboards and calibration, not solvency decisions.

**Coverage.** 30 tests. 14 check the functions' documented claims, 11 of them fuzzed at 2,000 runs;
seven deliberate breaks to the library each fail at least one of them. 6 run a stand-in game over
ten years of weekly draws on flat income. 5 check the games' own lines. 5 are invariants, checked
after every call while the stand-in game runs random sequences of draws and droughts under both
rules. `test/Proofs.t.sol` holds three symbolic proofs, run with Halmos rather than forge
(`halmos --contract EternalSeedProofs`; a bare `halmos` also picks up the invariant suites): Flow conserves the pool, the clamp at 100%, and headroom plus floor equals the pot.
Claims that need the solver to reason through multiplication and division together did not finish
in its time limit and rest on the fuzz and invariant tests. Mutation testing with Gambit 0.2.1
(Certora's tool, default operators): 62 mutants compile and the suite catches 61. The one it
misses removes the `seedBps >= BPS_DENOM` guard in `distributable()`, which the NatSpec there
describes as deliberate redundancy: without it the subtraction gives 0 as well. Not audited. Not
deployed.
