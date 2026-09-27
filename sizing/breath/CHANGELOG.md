# CHANGELOG: Breath

Newest first. Versions follow MAJOR.MINOR.PATCH. The library's history before it had its own
repository, every change to its logic included, is in Lettery Perpetual's CHANGELOG up to version
0.59.

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
