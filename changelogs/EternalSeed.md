# EternalSeed.sol changelog

Cumulative, newest first. No version in this file's history has changed a line of executable
code. Every entry is documentation, and the executable lines are byte-identical from v1.0 to
v1.7.

---

## v1.7

Delta pass on v1.6.

**ES-09.** PROBLEM: V16 sat under HYBRID VARIANTS while the hybrid range read V13 to V15,
excluding a member of its own group. SOLUTION: range extended to V16, with the composition
stated precisely. V16's floor is an absolute host-supplied obligation, not a proportional pot
fraction.

**ES-10.** PROBLEM: the taxonomy intro still called V6 the suite standard after v1.5 had
scoped V6's own entry to the prediction suite. SOLUTION: intro scoped to match; V16 named as
the standard for obligation-backed protocols.

**Cosmetic.** Two line-wrap artifacts from the v1.5 and v1.6 insertions, reflowed.

Pre-publication amendments within v1.7:

**ES-11.** PROBLEM: the "exactly 1" justification read that a non-integral quotient differs
from its ceiling by exactly 1, conflating the real quotient with its floor. SOLUTION: restated
as the floor and the ceiling of a non-integral quotient differing by exactly 1.

**ES-12.** PROBLEM: the large-delta backstop claimed the result exceeds pot and seedFloor
underflows. False for dust pots: at pot 1 with delta 10001, maxDistributable returns 1,
seedFloor returns 0, silently. SOLUTION: scoped with the counterexample printed. Superseded
within v1.7 by ES-14.

**ES-13.** PROBLEM: "becomes a literal Formulation A composition" overstated the relationship.
The protected value coincides at the moment of the call; the mechanism does not, since V16
enforces at maturity while Formulation A caps every period proportionally as the pot moves.
SOLUTION: reworded to anchoring at the moment of the call, in both locations.

**ES-15.** PROBLEM: `seedFloor()`'s dev block carried the line "See FORMULATION A SEMANTICS
in the library header" twice consecutively, an amendment-landing artifact of the same class as
ES-04. It was present in one lineage copy only, which is worth recording so the removal does
not later look like unexplained drift. SOLUTION: duplicate removed.

**ES-16.** PROBLEM: four changelog lines wrote NatSpec tag names as prose, and two of them sat
at line-initial position where Solidity parses them as real tags. The generated user
documentation for this library already contained changelog fragments spliced into its notice
text, visible in `solc --userdoc` output. A present defect rather than a future hazard.
SOLUTION: tag names written without the leading at-sign. Standing rule for this suite: never
write a literal tag inside a doc comment.

**ES-17.** PROBLEM: V16 said the solver "guarantees the maturity pot", while BreathEngine's
own documentation says its floor guarantee is exact with respect to its projection model and
can diverge from a host whose arithmetic differs. Two files in one library disagreeing about
the same property. SOLUTION: reworded to "holds the maturity pot to the floor it is given".

**ES-18.** PROBLEM: "Origin: suite standard from v1.6 onward" reads as self-referential now
this file has its own v1.6. SOLUTION: qualified as a suite contract version.

**ES-14.** PROBLEM: ES-12's replacement scoping stated a sufficient condition as a necessary
one. A pot below BPS_DENOM wei still reverts at a large enough delta (pot 5000, delta 20001:
maxDistributable returns 10000, exceeding pot), so the paragraph promised silence where the
library in fact reverts. SOLUTION: replaced with the exact condition,
`delta > BPS_DENOM AND pot * (delta - BPS_DENOM) >= BPS_DENOM`, verified by exhaustive
enumeration against actual behaviour. Both silent families kept as illustrations and the joint
dependence on pot and delta stated explicitly.

---

## v1.6

Delta pass on v1.5.

**ES-04.** PROBLEM: the v1.5 ROUNDING insert split the seedFloor bullet from its description,
stranding a subjectless paragraph. SOLUTION: description moved back under its bullet.

**ES-05.** PROBLEM: the decomposition into invariant floor plus current-rate fraction was
printed as exact; it is off by up to 1 wei because the terms truncate independently.
SOLUTION: qualified, with the subtraction form named as the definition.

**ES-06.** PROBLEM: the third out-of-range case claimed seedFloor surfaces it; it does so only
when the delta also exceeds BPS_DENOM. SOLUTION: subcase stated, absence of a backstop
acknowledged.

**ES-07.** PROBLEM: distributable's boundary guard is redundant, since seedReturn clamps
first, and that was undocumented. SOLUTION: recorded as deliberate redundancy for legibility.

**ES-08.** PROBLEM: projectedSeedContribution's `seed * draws` is an unbounded multiplication
with no overflow note. SOLUTION: overflow sentence added; it reverts, and the function is
tooling only.

---

## v1.5

Accuracy pass.

**ES-01.** PROBLEM: the single-fraction closed forms printed for seedFloor, the invariant
floor and distributable are not equivalent to what the library computes. Integer division
truncates the subtrahend, so each closed form returns up to 1 wei less than the subtraction
form, and in distributable the closed form broke the file's own conservation invariant.
SOLUTION: all three restated in subtraction form, ROUNDING block added, integrators directed
to call the function rather than reimplement the fraction.

**ES-02.** PROBLEM: V16 conflated the seed rollover rate with the distribution rate.
SOLUTION: rewritten. The seed fraction is a host parameter; the distribution rate is what the
solver moves. The three bounds are restated as host-side policy rather than solver properties,
and the minimum-rail entry records that BullsEth releases the rail below the floor (v1.14,
H-06).

**ES-03.** PROBLEM: V6's unqualified "suite standard" competed with V16's claim; the
out-of-range paragraph lacked its third case; seedReturn's rounding block was unlabelled.
SOLUTION: all three addressed.

**RE-01.** PROBLEM: the superseded SeedEngine.sol reference repo published a different
mechanism under the same name and number, "Variant 16: Breathing Seed". SOLUTION: V17 Liquid
Breathing added as an adjacent variant so the two never share a name. Taxonomy heading updated
to seventeen.

---

## v1.4

NatSpec audit pass. seedFloor redocumented as moving with payoutBps and therefore not the
invariant floor, with the FORMULATION A SEMANTICS block added to define both (L-01). An
unqualified "never" removed from maxDistributable, the fourth such location and one the v1.3
pass missed (I-01). Out-of-range behaviour restated accurately: Formulation A reverts via
checked arithmetic, Formulation B clamps (I-02). projectedSeedContribution's direction-of-error
claim corrected to conditional (I-03). Rounding direction documented as deliberate (I-04). V16
entry completed with an implementation reference to BreathEngine.sol.

## v1.3

Semantic accuracy pass. "Permanent" and "never" language removed from three locations and
replaced with "season-locked", with explicit acknowledgement that defined exit paths exist at
settlement and dormancy. The WHAT "ETERNAL" MEANS block added to disambiguate the name for
auditors and integrators.

## v1.2

No changes from v1.1. Version tag only.

## v1.1

PARAMETER CONSTRAINT section added, documenting that payoutBps and maxPayoutBps must not
exceed BPS_DENOM and that the host must validate at construction. Companion whitepaper
recommendation noted for the variant taxonomy.

## v1.0

Initial delivery. Canonical taxonomy and reference implementation extracted from the DYBL
suite.
