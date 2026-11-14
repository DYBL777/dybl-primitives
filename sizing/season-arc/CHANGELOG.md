# CHANGELOG: SeasonArc

Current version: 1.1.6. Code changes are listed first, newest first; versions that changed only
comments or documentation (1.1.1 to 1.1.6) are summarised after them.

Instructions hash (runtime code with the metadata trailer left off; how to compute it is in
README.md, "Checking a linked copy"), for the settings in `foundry.toml`:

| Version        | Instructions hash                                                    |
|----------------|----------------------------------------------------------------------|
| 1.1.5, 1.1.6   | `0xc4f7e21e0da4c59421372ffc0770135c73369dd7d2498c115b6a0281c0b6b2fb` |

Versions follow MAJOR.MINOR.PATCH. The solver's history before it had its own
repository, every change to its logic included, is in Lettery TF's CHANGELOG up to version 0.998.

**[1.1.0]** PROBLEM: the fallback was entered whenever the solver returned its floor, and the
  solver returns its floor in two cases: flat payments running the pot dry, and flat payments
  fitting while nothing steeper does. In the second the arc had not failed, yet the draw was
  paid by the fallback. Lettery TF's models found it (one sampled case in about 1,560, from a model
  not in this repository). SOLUTION: at the floor the
  forward walk is run once more at flat. If flat leaves anything, the draw pays what the last one
  did (bind ARC) and the closing draw takes the surplus; only when flat runs dry does the
  fallback pay. `test/SustainedFallback.t.sol` pins a boundary case: a pot of $1,820,824 that flat
  payments of the last amount carry to the end with about $1,032 to spare.
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

**Instructions hash published after 1.1.6** (library unchanged). PROBLEM: hosts checked the
  linked copy by its whole code hash, which includes the metadata trailer; the trailer records
  paths and remappings, so a correct copy built in another tree, or on another forge version,
  failed the check. SOLUTION: the instructions hash (trailer left off) is published per release
  here and in README.md, with how to compute it; `test-deployable/DeployableBuild.t.sol` pins it,
  and tests that a trailer change keeps the hash and an instruction change moves it. A changed
  constant in the library fails the pin while the 1,310-byte size check still passes.

**Tests added after 1.1.6** (library unchanged). PROBLEM: the library accepts an opening of 0% to
  100%, but the suites fuzzed it only from 10% to 50%, and no test measured what a shrinking crowd
  or money already in the pot does at a given opening. SOLUTION: `test/Opening.t.sol`, 17 tests:
  a steady season at openings from 0.01% to 100%; the highest opening a steady shrink, a longer
  season and a sudden exodus each allow without a draw paying less than the one before, pinned
  from both sides; a fuzzed check that players leaving does not lower the prize per ticket; a
  carried seed at a high opening, with and without a host-side cap on the opening; the same crowds
  with the last payment scaled by the crowd, as Lettery TF passes it; a zero opening and one that
  rounds to nothing; a late outflow from the pot. `test/StandIn.t.sol` and
  `test/Invariants.t.sol` now fuzz the opening from 0.01% to 100%.

**Tests added with 1.1.6** (library instructions unchanged): `test/Proofs.t.sol`, five Halmos
  proofs of the edges of `size`; `test/Exhaustive.t.sol`, seven grids of 40,000 calls checked
  against the rule coded apart from the library; `test/Link.t.sol`, one code hash per build and a
  host linked to an empty address reverting; `test/Gas.t.sol`, the gas figures KNOWN_ISSUES quotes,
  now asserted; `test/Ceiling.t.sol`, pots from 5e14 to 1e60 and the point where the arithmetic
  overflows; `test-deployable/`, the build that deploys, run on its own. The grids catch six
  mutations of the fallback's correction band, and the gas test three of the solver's early exit,
  that the suite before them missed. Mutation-testing result in DESIGN.md.

**Tests added without a change to the library** (library unchanged at 1.1.4): `test/Invariants.t.sol`, an
  invariant suite running seasons of random length, opening and return shares through the
  stand-in game, with crowds that arrive, leave or stop buying. After every draw it checks that no
  draw pays more than the pot, the opening is its share, the arc does not size down, an arc payment
  leaves something for later, the closing draw empties the pot and every unit is accounted for.
  A closing draw that keeps a sliver, an oversized opening, an arc that shrinks, or a removed
  fallback each fails it. Unit tests also pin the two input guards, the no-draws-left case, a huge
  income against the pot (the first draw binds), a small income against the pot (the last draw
  binds), and the fallback's correction loop on inputs where the closed form's first guess is too
  high. The fallback fuzz now checks that a zero answer means not even one unit
  is affordable.

## Comments and documentation

**After 1.1.6.** KNOWN_ISSUES names all three ways a last payment of zero can reach the library
mid-season, each of which makes the next draw an opening again.

Versions whose library instructions did not move. The compiler appends a hash of the source text
to the runtime bytes, so a comment change still gives the library a new address when deployed.

**1.1.6** The comment on the last-draw line in `_leftover`, KNOWN_ISSUES and DESIGN.md said that
leaving the returned share out after the last draw made the arc shallower and changed what the
solver pays. It changes no answer: every caller asks only whether the walk ends above zero. The
comment and DESIGN.md now say so, and the KNOWN_ISSUES entry is gone. KNOWN_ISSUES now says which
build to deploy from, and why. Compiled code identical to 1.1.5 with the metadata hash excluded.

**1.1.5** Comments cut to what the code does and its traps; the design reasoning, rejected
designs and the evidence for each claim moved to the new DESIGN.md. The "40,000 random cases"
comment now names `sim/arc_fuzz.py` and says it checks Python against Python, with the Solidity
tests named beside it. A figure from a model not in this repository removed. Compiled code
identical to 1.1.4 with the metadata hash excluded, at the same sizes (1,310 runtime bytes built
alone, 1,464 built with the tests).

**1.1.4** Comments that overstated the library corrected. The solver's arc does not choose a
decline, but the fallback can step down once; the one-step collapse shape holds with the last
payment passed unscaled; the $9,606.23 example is at a 29.9% return share; the sibling rule is
named SeedGlide. Test comments, the README, KNOWN_ISSUES and the Python sim now match what the
code and tests show, two figures the docs quote are now asserted where they are measured, and the
sim's coverage table uses the return share it models.

**1.1.3** The `SUSTAINED` bind documented as able to carry zero, and an error's NatSpec no longer
names one host's error.

**1.1.2** Comments that narrated superseded states (the pre-fallback collapse shape, a removed
cap, the old search ceiling, a forward promise) rewritten as the rules and reasons that stand.

**1.1.1** Two comments described the shape of a crowd collapse as it was before the flat-payment
fallback existed (a plateau of about twenty weeks, then one fall at draw 37). They now say what
the library does: one step down in the week the crowd leaves, then flat, as `test/StandIn.t.sol`
measures.
