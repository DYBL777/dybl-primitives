# CHANGELOG: Breath

Current version: 1.0.1.

Newest first. Versions follow MAJOR.MINOR.PATCH. The library's history before it had its own
repository, every change to its logic included, is in Lettery Perpetual's CHANGELOG up to version
0.59.

**[1.0.1]** PROBLEM: the library's comments here and in Lettery Perpetual's copy had drifted
  apart, and this copy still gave the old early-collapse figures for the floor (a 73% cut at 55%,
  46% at 25%), which the game's model does not reproduce. SOLUTION: one comment set, carried in
  both copies, with the figures as the model gives them; the compiled code is unchanged.
  Tests: no test ran a whole game on the library, and `spare()` was tested one call at a time.
  `test/StandInGame.sol` is the smallest game that runs on Breath, and `test/StandIn.t.sol` runs
  it in eight tests over up to twenty years, including `spare()` levelling a pot that would
  otherwise keep growing, and a draw refused as dust not becoming the next draw's starting point.
  The figures name the model they come from (`sim/` in Lettery Perpetual's repository), a
  sentence broken across two lines is joined, and the fuzz tests are pinned at 2,000 runs, as in
  EternalSeed.

**[1.0.0]** PROBLEM: the library lived inside Lettery Perpetual, so it could be read and tested
  only through that game. SOLUTION: extracted with its library-level tests. The compiled bytecode is
  identical to the copy Lettery Perpetual 0.59 compiles in, checked by hashing a harness that calls
  every function under that host's compiler settings, metadata excluded.
  Tests: 17 library-level tests carried across, run through a stand-in host with no game around
  it, plus 3 new. Two rules had no library-level test once the game was gone: removing the rise
  rail, or making the fast average follow rises and falls at the same speed, left every carried
  test passing. Each now has a hand-computed test. The third new test pins the dust guard cutting a
  payout below the fall rail.
  Comments rewritten to describe the library rather than its first host. One claim corrected: the
  library said only an empty pot may cut a payout harder than the fall rail, and the dust guard
  does too (a draw sized under minDraw pays nothing).
  Tests added after publication, library unchanged: `test/Invariants.t.sol`, an invariant suite
  driving a minimal game through random draws, droughts and surges; it checks the pot cap, the
  dust guard, both rails and accounting after every draw.
  Tests added later, library unchanged. PROBLEM: mutation testing with Gambit found changes to
  the library that no test caught: the pace set by the trend at both ends of the band and inside
  it, the size of the creep step, the size of a `spare` offer, `payout` on a game not started or
  an empty pot, a return share of the whole, and a slow average with no weight. SOLUTION:
  `test/Pace.t.sol` pins the pace and the creep to figures worked from the averages;
  `test/Edges.t.sol` pins the early returns, the refused return share and both `spare` limits;
  `test/Bounds.t.sol` adds the zero-weight rejection. The suite catches 354 of 355 mutants
  (KNOWN_ISSUES).
