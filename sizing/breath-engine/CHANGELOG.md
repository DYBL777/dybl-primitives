# CHANGELOG: BreathEngine

Newest first. One change to the library's executable code in its history: `isInsolvent()` at
1.3. Every other version changed documentation or tests only, and the compiled code is
identical from 1.3 on.

---

## Code and tests

**1.4** PROBLEM: the two test suites imported the library from paths that do not exist in
this repository, so `forge test` could not compile them. SOLUTION: both import
`src/BreathEngine.sol`. PROBLEM: nothing at library level checked that `solve()` returns the
largest safe rate rather than merely a safe one, or pinned three documented behaviours: an
insolvent input returning 0 without reverting, `potHealth()` gating as the exact ratio would, and
the free 1 bps rate at exact equality. SOLUTION: four tests. Each fails against a deliberately
broken library (an off-by-one solver, the insolvency guard removed, `potHealth()` rounding up).
12 tests, all passing: 8 probes and a fidelity suite of 4, 3 of them fuzzing the library against
a verbatim replica of the solver inside BullsEthCRE 1.17.
PROBLEM: no test ran whole seasons of re-solving. SOLUTION: `test/Invariants.t.sol`, an invariant
suite of random seasons checking that every rate holds the floor in the model, that a solvent
season stays solvent and that it ends at or above its floor; a solver one basis point too high,
or a projection that overstates income, fails it. `test/Proofs.t.sol` adds three Halmos proofs.

**1.3** PROBLEM: `solve()` returns 0 both when the floor cannot be reached and when the state
is solvent with no headroom (stock exactly at the floor with no income, for example), so a host
testing the rate alone signals distress when there is none. SOLUTION: `isInsolvent()`, true
when even distributing nothing cannot reach the floor; hosts pair it with a zero rate.

**1.0** Initial extraction from the DYBL suite: `sim()`, `solve()`, `updateEMA()`,
`potHealth()`.

---

## Documentation versions (no change to compiled code)

**1.4.** Load-bearing guards in `solve()` and `sim()` documented for porters, with the exact
range where removing `solve()`'s guard reverts. Missing parameter tags added. A third overflow
site documented. `sim()`'s rounding direction corrected (it books slightly less loss than exact
arithmetic) and scoped: the floor guarantee is exact against `sim()`'s own model, and the gap
appears only against a host that floors its pool and its seed in two steps, BullsEthCRE among
them, with measured figures and their parameters. An unsupported claim about behaviour above a
100% rate replaced with what is known. The in-file changelog and version tags removed; history
lives here. Change Date aligned to 1 February 2030.

**1.3.** Supported input domain documented (gas grows with `periods`; `maxBreathBps` up to
10,000). Host integration note corrected: BullsEth no longer clamps to a minimum rail. Boundary
note for porters. `potHealth()` rounding documented. Absolute claims softened.

**1.1 to 1.2.** Overflow bound on the revenue input documented. Host integration pattern
documented; a heading that claimed production use rewritten.
