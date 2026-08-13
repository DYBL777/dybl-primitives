# BreathEngine.sol changelog

Cumulative, newest first. One code change in the file's history: the nine-line
`isInsolvent()` helper at v1.3. Every other version is documentation.

---

## v1.4

NatSpec only. Executable lines byte-identical to v1.3 (diff-verified), so the v1.3 fidelity
proof against the BullsEthCRE v1.17 solver carries forward unchanged.

**BE-N-01.** PROBLEM: `solve()`'s `worstCase < floor` early return reads as an
optimisation. Removing it turns an insolvent input from a zero return into an underflow
revert: the search reaches `lo == hi == 0`, `mid == 0`, and `hi = mid - 1` underflows.
SOLUTION: porter note naming it load-bearing.

**BE-N-02.** PROBLEM: `updateEMA()` and `potHealth()` carried no parameter or return tags
while every other function had a full set. SOLUTION: tags added.

**BE-N-03.** PROBLEM: OVERFLOW ANALYSIS did not cover the `revPerPeriod * periods`
multiplication in `sim()`'s early return. SOLUTION: third site documented, bound
`revPerPeriod <= type(uint256).max / periods`.

Amendments landed within v1.4:

**BE-N-04.** PROBLEM: BE-N-03's rationale, that the multiplication overflows at a lower
threshold than the loop it replaces, is false. Both revert on identical inputs: a product
overflow implies the sum overflows, and checked addition reaches the same total. SOLUTION:
bound kept, mechanism removed.

**BE-N-05.** PROBLEM: `sim()`'s early return is load-bearing in a second undocumented way.
For `seedBps > BPS_DENOM` the loop's `BPS_DENOM - seedBps` underflows, so the early return
is what keeps those inputs total (when `periods >= 1`; at `periods == 0` the loop never
runs). SOLUTION: documented in the same porter voice as BE-N-01.

**BE-N-06.** PROBLEM: BE-N-01's revert claim is not universal. Guardless, an insolvent
input returns 0 without reverting once the 24 iterations exhaust before `mid == 0` is
evaluated. SOLUTION: claim scoped. Boundary is exact: reverts for every
`maxBreathBps <= 2^24 - 2`, stops at `2^24 - 1` and above. It therefore holds across the
whole supported domain and all but the top point of the convergence domain.

**BE-N-07.** PROBLEM: `sim()` described its truncation of `lost` as conservative and safe,
which is the opposite direction. SOLUTION: direction corrected.

Amended before publication after review. The first correction said `solve()`'s floor
guarantee can be missed by a few wei, stated without qualification. That is wrong inside the
library: the search tests every candidate rate against `sim()` directly and only advances on
a verified result, so the guarantee is exact with respect to this projection model. The gap
exists only against a host whose real per-period arithmetic differs from `sim()`'s single
floored step. The measured figures also carried no
parameters, so nobody could reproduce them; a second measurement at different inputs produced
the same shape and different numbers. Rewritten to scope the claim and to state the
parameters beside the figures.

**BE-N-09.** PROBLEM: the rewrite above then named BullsEthCRE as not being a two-step host,
which is false, and it exempted the one production host the caveat actually applies to. Its
projection `_simGeomPot` does use a single floored step, but its settlement path floors twice:
the weekly pool out of the pot, then the seed rollover out of that already-floored pool. That
is precisely the pattern the paragraph warns about. The evidence cited did not cover the claim
either: the differential fidelity suite compares one projection against another and says
nothing about settlement arithmetic. Measured over 29 draws at 10k, 100k and 1M USDC and
breath rates of 500, 1000 and 1500 bps, the settled pot ends 3 to 11 wei below the projection,
never above. SOLUTION: BullsEthCRE restated as the canonical example of a two-step host with
its own measured figures; what the fidelity suite genuinely proves stated separately; and two
explicit remedies given, single-floor settlement or a padded floor, with the recommendation
that each host shape gets one differential test between `sim()` and its own settlement path.

**BE-N-08.** PROBLEM: the input-domain section justified the 10000 ceiling by asserting the
trajectory becomes non-monotone in rate above 100%. Never demonstrated, and a sweep of rates
to 40000 across many configurations produced no non-monotone case; above the clamp threshold
`sim` flattens to `revPerPeriod`, which is monotone. SOLUTION: the assertion is replaced with
what is actually known. Maximality is unverified outside the supported domain and the
restriction stands as caution rather than as a demonstrated failure.

**Build hazard (not a library finding).** PROBLEM: changelog prose written with literal
NatSpec tags fails to compile, because Solidity parses them as real tags. SOLUTION: prose
written without leading at-signs. Applies to every future doc pass in this suite.

---

## v1.3

CODE: `isInsolvent()` added (BE-L-01), so hosts test distress against the insolvency
predicate rather than the ambiguous zero return. Zero-return meanings list gained case (e),
solvent with zero headroom.

NATSPEC: SUPPORTED INPUT DOMAIN added (BE-L-02 periods gas hazard with measured figures,
BE-I-04 `maxBreathBps <= 10000` semantic domain). L-01 corrected: BullsEth stopped clamping
to `breathRailMin` at v1.14 (H-06), so the clamp is now described as the original monolith
pattern with porters told to check their own host (NS-03). Boundary-equality porter note
(BE-I-03). PROVEN IN PRODUCTION renamed HARDENED ACROSS THE DYBL SUITE to match its body,
and the absolute claim about no production protocol softened (BE-I-01). `sim()` inventory
reworded to a host wrapper note (BE-I-02).

Amendments within v1.3: `potHealth()` truncation note corrected to state that gate outcomes
are unchanged for integer thresholds (BE-I-06). Audit-pass count reworded from "seven" to
"repeated" (RA-02). Gas figure corrected from 24 sims per solve to 25 (RA-01).

## v1.2

`revPerPeriod` overflow bound documented with a realistic magnitude argument. No code
changes.

## v1.1

PROVEN IN PRODUCTION section rewritten (M-01-NS). Host integration pattern documented
(L-01). Origin year corrected (I-01). `potHealth()` added to the function inventory (I-02).
Convergence bound noted (I-03). Em-dashes removed (I-04).

## v1.0

Initial extraction from the DYBL suite.
