# KNOWN_ISSUES: BreathEngine

Limits of the library itself. What a particular host does with it, and that host's own limits,
are in the host's repository.

**A zero rate is ambiguous.** `solve()` returns 0 for an empty stock, zero periods, a zero
ceiling, a floor that cannot be reached, and a solvent state with no headroom. Only the fourth
is distress. A host tests `isInsolvent()` before treating a zero rate as distress.

**There is no minimum rate.** On structural insolvency the answer is 0, so prizes stop rather
than continuing at a minimum. A host that wants a minimum applies it itself, knowing that
paying a minimum into a collapse spends the capital the floor exists to protect.

**Gas grows with `periods`.** About 8,300 gas per period per solve (25 projections of the full
horizon). Measured at about 246k gas at 29 periods and 8.29M at 1,000; around 3,600 periods
exceeds a 30M block. The library does not cap `periods`. The supported range is up to 366, and
a host deriving `periods` from configuration bounds it before calling.

**`maxBreathBps` above 10,000 is outside the supported domain.** The search still converges and
stays floor-safe there, but whether its answer is the maximum is not verified.

**The floor guarantee is exact against `sim()`'s model, not against every host's arithmetic.**
A host that floors its pool and its seed in two separate steps loses slightly more each period
than `sim()` models, so its real stock can end a few units below the projection. BullsEthCRE
settles this way. A new host settles in one floored step to match, or pads the floor it passes.

**The library trusts its inputs.** It cannot read the host's books. A revenue estimate the host
does not actually receive produces a confident wrong answer. Pathologically large inputs
revert on overflow rather than returning.

**Each host compiles its own copy.** Every function is internal. Two hosts built with different
compiler settings carry different bytecode for the same source.

**BullsEthCRE, its first host, is still in development.** The library is tested against the solver
in BullsEthCRE 1.17. The host's prize structure is not final, and the settlement gap above is
measured against that version.

**Coverage.** 13 tests. 8 probe documented edge cases: fuzzing that `solve()` holds the floor and
that one basis point more would breach it, that an insolvent input returns 0 without reverting,
that `potHealth()` gates exactly as the true ratio would, and the rounding case at exact equality.
4 form the fidelity suite, 3 of them fuzzing the library against a replica of BullsEthCRE 1.17's
solver: they agree except at the one documented boundary, where paying nothing lands exactly on
the floor. 1 invariant suite runs whole seasons, re-solving every period with income at or above
the estimate, and checks that each rate holds the floor in the model, that a solvent season stays
solvent and that it ends at or above its floor. `test/Proofs.t.sol` holds three symbolic proofs
run with Halmos; the solver's search is too deep for one. Not audited. Not deployed.
