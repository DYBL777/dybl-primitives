# EternalSeed.sol changelog

Newest first. Code and test changes are listed individually. Documentation-only versions are
summarised at the end.

The library's compiled code has not changed since 1.3, the earliest version available for
comparison. Every version since has changed documentation only, apart from one parameter rename in
2.0 that changes the source text but not the compiled code. From 2.0 a test suite pins the
behaviour the documentation describes.

---

## Code and tests

### 2.0

**Problem:** the library's headline claims were stated in prose with no test behind them:
conservation (seedReturn plus distributable equals the pool), the exactly-one-unit gap between the
closed forms and the functions, the difference between seedFloor and the invariant floor, the
exact condition under which an oversized ceiling is surfaced, and the projection's overflow
behaviour.

**Solution:** `test/EternalSeed.t.sol`, 14 tests, 11 of them fuzzed at 2,000 runs, each named for
the claim it checks. Mutation-checked: seven deliberate breaks to the library each fail at least
one test. Removing the guard in distributable() that the documentation describes as redundant
fails none, which confirms that description.

**Problem:** nothing showed what the rule does to a pot over time; the tests check single
calls only.

**Solution:** `test/StandInGame.sol`, the smallest game that holds a pot under either rule, and
`test/StandIn.t.sol`, 6 tests on it over ten years of weekly draws: every unit accounted for, a
held pot paying above its income once built, a seeded pot growing bigger than an unseeded one
(and paying less in year one), a held pot paying through a year with no income, Floor and Flow
tracking each other at the same effective rate, and the invariant floor holding at the ceiling
rate.

**Problem:** each game writes its own line of the rule, and nothing checked that line against the
reference.

**Solution:** `test/HostConformance.t.sol`, 5 tests fuzzing a copy of each game's line against
seedReturn() and distributable(). Lettery Perpetual 0.59, Lettery TF 1.2.1 and BullsEthCRE 1.17
match exactly. SeedTogether 0.65 keeps one unit more in its seed exactly when there is a
remainder, the known rounding difference, and the test pins that gap.

**Problem:** the projection helper named its rate `breathBps`, the same quantity Formulation A
calls `payoutBps`.

**Solution:** renamed to `payoutBps`. Compiled bytecode is identical before and after, and
identical to 1.3.

### 1.0

Initial reference implementation: maxDistributable(), seedFloor(), seedReturn(), distributable(),
projectedSeedContribution().

---

## Documentation versions (no change to compiled code)

**2.0.** Header rebuilt around two axes, retention (Floor, Flow) and ending (Compound, Port,
Spend-down, Return), replacing seventeen numbered variants. The seed is defined as the pot under a
retention rule rather than a reserve beside it. Added: what actually returns under Flow (reseed plus
the routed share of missed prizes), the grid of hosts, compositions, pointers to the four sizing
solvers, and a lineage paragraph. Host-specific wording (a named lender, settlement exits, a pot
that always grows) replaced with wording that holds for every host. The in-file changelog is
removed; history lives here only. Duplicate line in seedFloor's documentation removed. Where the 1.x
variants went: V1 to V4 into Floor and its ceiling policy; V5 into Compositions (Dual Floor); V6 to
V12 into Flow and its rate policy; V13 to V15 into Compositions; V16 into Sizing Solvers; V17 into
the adjacent yield-funded seed.

**1.7.** The out-of-range paragraph states the exact condition under which an oversized ceiling is
surfaced, replacing two earlier wordings that were each wrong in one direction. Rounding
justification corrected. Composition of the ADRP-governed variant stated precisely.

**1.5 to 1.6.** Closed forms restated in subtraction form: the printed single-fraction versions
were one unit off and, for distributable(), contradicted the conservation property. Variant scope
and naming corrections, including renumbering a variant that collided with a superseded
repository.

**1.4.** seedFloor documented as moving with the current rate; the invariant floor defined
separately. Rounding direction documented.

**1.3.** "Permanent" and "never" wording replaced with season-locked wording and defined exits.

**1.1 to 1.2.** Parameter constraints documented.
