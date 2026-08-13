# Provenance

Where each primitive came from. This is the history of the ideas. For the history of the
files, see `changelogs/`.

Nothing here is copied from the source repositories. Where a claim needs evidence, it links.

---

## The line

Everything in this library descends from **Lettery S1**, a 42-character lottery contract
that introduced the Eternal Seed: a fraction of the pot ring-fenced from distribution and
compounded rather than paid out. That contract is the root of the whole suite.

Two branches grew from it. A **prediction branch** (BullsEth, Crypto42, Weather32,
NearestTheETH, Pick432, Chainlink20) and a **yield branch** (Lettery777, Lettery_Aave_1Y,
SeedTogether). The primitives here were extracted from the prediction branch, where they
were hardened hardest, but they appear in both.

---

## BreathEngine

**Origin:** the geometric solver inside `BullsEthCRE`, itself a generalisation of the
static seed-return rate used across earlier games.

**Where it was hardened:** repeated audit passes across BullsEth, Lettery777, Weather32 1Y,
Pick432 1Y, NearestTheETH and Lettery_Aave_1Y.

**The finding that shaped it:** an absolute distribution floor was forcing roughly one
percent of the pot out every period even during a collapse, and the distress branch was
spending at its rail minimum at exactly the moment it should have stopped. The fix, recorded
as H-06, releases the rail below the floor and returns zero on structural insolvency:
distributing a minimum into a collapse spends the capital the floor exists to protect. That
decision is why this library has no minimum-rail concept, and the reasoning is documented in
the file so a porter cannot reintroduce the fault by accident.

**Verification:** differential fuzzing against a verbatim replica of the `BullsEthCRE` v1.17
solver, byte-equal across thousands of runs except at one documented boundary. The
differential suite ships in `test/`.

**Reference contract:** https://github.com/DYBL777/BullsEthCRE

---

## EternalSeed

**Origin:** Lettery S1 (2025). The invariant floor, the fraction of the pot that no
governance action can distribute during a season, is the original invention.

**How it evolved:** the floor formulation (A) was joined by a flow formulation (B), a
fraction of each period's pool rolling back into the pot, which became the suite standard
across the prediction games. The two are complementary rather than competing, and their
composition generates the hybrid variants.

**Earlier publication:** a sixteen-variant taxonomy was published under BUSL as
`SeedEngine.sol` in the DYBL `The-Eternal-Seed` repository. That repository is superseded.
Its variant numbering does not match this one, and its reference implementation carries
known accounting issues. Anything citing "Variant N of the Eternal Seed" should cite this
file, not that one. The two taxonomies are reconciled in the companion paper; the one
collision that mattered, both documents using "Breathing Seed" for different mechanisms, is
resolved here by renumbering the older concept to V17.

---

## On reading the source contract

`BullsEthCRE` is the reference these extractions are verified against and it is public. It
is also a 70KB monolith that cannot be deployed under EIP-170, and it is frozen: its role
now is to be the thing new extractions are proven equal to, not to ship.

Its own documentation carries open items listed in that repository's `KNOWN_ISSUES.md`.
Read that file alongside the contract.

---

## Order of events

Dates are deliberately absent. Earlier versions of these files carried month-level dates that
turned out to be unreliable, so the sequence is recorded and the dates are not.

1. Lettery S1. The Eternal Seed appears, in its floor formulation.
2. The prediction and yield branches diverge. The flow formulation becomes the suite standard.
3. The geometric solver is introduced, and later hardened by the H-06 rail release.
4. BreathEngine is extracted as a standalone library and proven against the monolith.
5. The EternalSeed taxonomy is extracted.
6. Both are hardened to their current versions and published here.
