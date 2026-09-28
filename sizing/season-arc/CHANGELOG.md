# CHANGELOG: SeasonArc

Newest first. Versions follow MAJOR.MINOR.PATCH. The solver's history before it had its own
repository, every change to its logic included, is in Lettery TF's CHANGELOG up to version 0.998.

**[1.1.0]** PROBLEM: the fallback was entered whenever the solver returned its floor, and the
  solver returns its floor in two cases: flat payments running the pot dry, and flat payments
  fitting while nothing steeper does. In the second the arc had not failed, yet the draw was
  paid by the fallback. Lettery TF found it in one sampled case in about 1,560: a pot of $406,000
  that flat payments would have carried to the end with $249 to spare. SOLUTION: at the floor the
  forward walk is run once more at flat. If flat leaves anything, the draw pays what the last one
  did (bind ARC) and the closing draw takes the surplus; only when flat runs dry does the
  fallback pay. `test/SustainedFallback.t.sol` pins a boundary case.
  Every model that ports the rule, `sim/arc_fuzz.py` here and Lettery TF's raid, player-return,
  rebate, trace and weighting models, gave output identical to the last character before and
  after the change, so no published figure moves.

**[1.0.0]** PROBLEM: the solver was compiled into Lettery TF, so it could be reused only by
  copying it, and every host carrying its own copy paid for it in bytecode. SOLUTION: extracted
  into its own repository with its tests and the Python fuzzer. `size` is now `external`, so a
  host links one deployed copy; the solver's logic is otherwise the logic Lettery TF v0.998
  compiled in, and its comments now describe it as a library with hosts rather than as part of
  one game. A stand-in game (`test/StandInGame.sol`) runs whole seasons through the library
  without a host, with a fuzzed season that requires no draw to pay more than the pot holds.

---

**Tests added without a change to the library** (still 1.1.3): `test/Invariants.t.sol`, an
  invariant suite running seasons of random length, opening and return shares through the
  stand-in game, with crowds that arrive, leave or stop buying. After every draw it checks that no
  draw pays more than the pot, the opening is its share, the arc never sizes down, an arc payment
  leaves something for later, the closing draw empties the pot and every unit is accounted for.
  A closing draw that keeps a sliver, an oversized opening, an arc that shrinks, or a removed
  fallback each fails it.

## Comments and documentation

Versions whose library instructions did not move. The compiler appends a hash of the source text
to the runtime bytes, so a comment change still gives the library a new address when deployed.

**1.1.3** The `SUSTAINED` bind documented as able to carry zero, and an error's NatSpec no longer
names one host's error.

**1.1.2** Comments that narrated superseded states (the pre-fallback collapse shape, a removed
cap, the old search ceiling, a forward promise) rewritten as the rules and reasons that stand.

**1.1.1** Two comments described the shape of a crowd collapse as it was before the flat-payment
fallback existed (a plateau of about twenty weeks, then one fall at draw 37). They now say what
the library does: one step down in the week the crowd leaves, then flat, as `test/StandIn.t.sol`
measures.
