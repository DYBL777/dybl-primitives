// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1
// Licensor:       DYBL Foundation
// Licensed Work:  EternalSeed.sol
// Change Date:    24 February 2030
// Change License: MIT

pragma solidity ^0.8.24;

/**
 * @title  EternalSeed
 * @author DYBL Foundation
 * @notice Canonical reference implementation and taxonomy of the Eternal Seed primitive.
 *
 *         The Eternal Seed is the foundational concept of the DYBL suite. Every game
 *         in the suite uses one of the two formulations described here. The functions
 *         are one to three lines each. The primary value of this file is the taxonomy
 *         and variant mapping, which constitutes original intellectual work.
 *
 *         WHAT "ETERNAL" MEANS IN THIS CONTEXT
 *
 *         Eternal refers to the seed's protected, compounding role within the season,
 *         not to its irrevocable presence in the contract forever. The seed is
 *         season-locked: ring-fenced inside the pot, protected from treasury withdrawal,
 *         and compounding draw-on-draw for the full duration of the season.
 *         Defined exit paths exist at settlement (return to VC or distribution to players)
 *         and at dormancy or failed pregame (return to deploying party).
 *         The seed is permanent within the season. It is not permanent beyond it.
 *
 * @dev    TWO FORMULATIONS
 *
 *         Formulation A (Seed-as-Floor):
 *           A structural floor on the pot. A fraction of the pot cannot be
 *           distributed for the duration of the season. It sits there season-locked,
 *           compounding via Aave. The pot has a season-locked floor that grows with
 *           it (see FORMULATION A SEMANTICS below for the invariant floor definition).
 *           At settlement or dormancy the floor is released through defined exit paths.
 *           Origin: Lettery S1 v1 (2025).
 *           Functions: maxDistributable(), seedFloor().
 *
 *         Formulation B (Seed-as-Flow):
 *           A recurring flow. A fraction of each weekly prize pool rolls back into
 *           the pot after distribution. The pot grows draw-on-draw through the season
 *           toward a climactic finale. The seed is not a floor; it is a compounding
 *           engine.
 *           Origin: suite standard from suite contract v1.6 onward (a game version,
 *           not a version of this file). Used in all current DYBL games.
 *           Functions: seedReturn(), distributable().
 *
 *         The two formulations are complementary, not competing. The breathing seed
 *         (V16) supersedes the static flow rate (V6); it does not supersede the floor
 *         concept. Formulation A returns in the hybrid variants (V13 to V16).
 *         V16 composes differently from V13 to V15: its floor is an absolute
 *         obligation supplied by the host, not a proportional fraction of the pot.
 *         Setting that obligation to seedFloor(pot, 0, maxPayoutBps) anchors it to
 *         the Formulation A invariant floor as valued at the moment of the call;
 *         the enforcement remains end-of-horizon (the solver holds the maturity pot
 *         to the floor it is given), not Formulation A's per-period proportional cap.
 *
 * @dev    FORMULATION A SEMANTICS (payoutBps AND THE TWO FLOORS)
 *
 *         payoutBps is the distribution rate currently committed by the host,
 *         governed within [0, maxPayoutBps] (see V2). maxPayoutBps is the season
 *         ceiling: the largest fraction of the pot that governance can ever
 *         schedule for distribution.
 *
 *         Two distinct quantities follow. Do not conflate them.
 *
 *         Invariant floor = pot - pot * maxPayoutBps / BPS_DENOM
 *           Independent of payoutBps. This is the original Lettery S1 invention:
 *           the last fraction of the pot that no governance action can distribute
 *           during the season, so the floor only rises under normal operation.
 *           Obtain it as seedFloor(pot, 0, maxPayoutBps). Do NOT reimplement it as
 *           pot * (BPS_DENOM - maxPayoutBps) / BPS_DENOM: see ROUNDING below.
 *
 *         seedFloor(pot, payoutBps, maxPayoutBps)
 *           = pot - pot * (maxPayoutBps - payoutBps) / BPS_DENOM
 *           The portion of the pot not reachable by further rate increases this
 *           period. This value MOVES with payoutBps (raising the rate raises it)
 *           and is therefore NOT the season-invariant protected minimum. Integrators
 *           wanting the protected minimum must use the invariant floor above.
 *           It equals the invariant floor plus the fraction at the current rate, up
 *           to 1 wei of rounding: the difference of the two floored subtrahends is
 *           either floor(pot * payoutBps / BPS_DENOM) or that value plus 1, depending
 *           on the remainders. The subtraction form above is the exact definition.
 *
 *         ROUNDING (Formulation A). Both quantities are defined by SUBTRACTION from
 *         pot, because that is what the implementation computes. The single-fraction
 *         closed forms, pot * (BPS_DENOM - maxPayoutBps + payoutBps) / BPS_DENOM and
 *         pot * (BPS_DENOM - maxPayoutBps) / BPS_DENOM, are NOT equal to them: integer
 *         division truncates the subtrahend rather than the result, so the closed forms
 *         return exactly 1 wei less whenever pot * (maxPayoutBps - payoutBps) is not a
 *         multiple of BPS_DENOM, and are equal otherwise. The gap is never larger: the
 *         floor and ceiling of a non-integral quotient differ by exactly 1. The
 *         library's direction is the conservative one (it protects the extra wei).
 *         Integrators needing the invariant floor must CALL seedFloor(pot, 0,
 *         maxPayoutBps) rather than reimplement the formula.
 *
 * @dev    PARAMETER CONSTRAINT (REQUIRED)
 *
 *         All functions in this library require:
 *           payoutBps <= BPS_DENOM (10000)
 *           maxPayoutBps <= BPS_DENOM (10000)
 *
 *         If payoutBps > BPS_DENOM or maxPayoutBps > BPS_DENOM:
 *           In Formulation A: maxDistributable() computes (maxPayoutBps - payoutBps)
 *           which underflows if payoutBps > maxPayoutBps, reverting in Solidity 0.8.x.
 *           seedFloor() computes pot - maxDistributable which could underflow similarly.
 *           In Formulation B: seedReturn() and distributable() divide by BPS_DENOM
 *           but seedBps > BPS_DENOM would return more than the full weeklyPool,
 *           violating the conservation invariant. Both functions therefore clamp
 *           at the boundary (see below).
 *
 *         Out-of-range behaviour differs by formulation and is deliberate:
 *           Formulation A reverts on invalid orderings via Solidity 0.8.x checked
 *           arithmetic (payoutBps > maxPayoutBps underflows and reverts).
 *           Formulation B clamps at the boundary (seedBps >= BPS_DENOM: the entire
 *           pool seeds, zero is distributable).
 *         A third case neither reverts nor clamps: maxPayoutBps > BPS_DENOM with the
 *         ordering payoutBps <= maxPayoutBps intact. maxDistributable() then returns a
 *         value computed against a ceiling above 100%. It is surfaced only when that
 *         value exceeds pot, so that seedFloor() underflows and reverts. Writing
 *         delta = maxPayoutBps - payoutBps, that happens exactly when
 *         delta > BPS_DENOM AND pot * (delta - BPS_DENOM) >= BPS_DENOM.
 *         Every other case is silent. Two silent families follow from that condition.
 *         Small pots absorb even a large delta through truncation (pot 1, delta 10001:
 *         maxDistributable returns 1, seedFloor returns 0). A delta at or below
 *         BPS_DENOM never trips it at ANY pot size (for example maxPayoutBps 12000,
 *         payoutBps 3000). In both families the functions return values that are
 *         meaningless against a ceiling that is not a fraction of the pot, and there
 *         is no backstop: host validation is the only defence.
 *         Note the condition is on the pot AND the delta jointly, not on either alone:
 *         a pot below BPS_DENOM wei still reverts at a large enough delta (pot 5000,
 *         delta 20001: maxDistributable returns 10000, exceeding pot).
 *         Neither path validates inputs itself; this is a pure math reference.
 *         The host constructor MUST validate all BPS parameters at deployment time.
 *         Never pass user-supplied BPS values to these functions without prior
 *         range validation.
 *
 * @dev    SEVENTEEN VARIANT TAXONOMY
 *
 *         The two formulations generate a design space of at least sixteen meaningful
 *         variants when composed with different protocol mechanics. V17 sits outside
 *         both formulations and is listed for completeness and to retire a naming
 *         collision. V6 (Formulation B) is the most widely deployed across the
 *         prediction suite; V16 is the standard for obligation-backed protocols.
 *         Variants V13-V15 are particularly novel and do not appear in any known
 *         deployed protocol.
 *
 *         This taxonomy belongs in a companion whitepaper. The NatSpec here is a
 *         structured index; the full variant analysis is a separate document.
 *
 *         FORMULATION A VARIANTS (Seed-as-Floor):
 *           V1  Static Floor        -- payoutBps fixed, maxPayoutBps fixed.
 *                                      No governance. Fully immutable.
 *           V2  Governed Floor      -- payoutBps owner-adjustable within [0, maxPayoutBps].
 *                                      Governance with a ceiling commitment.
 *           V3  Escalating Floor    -- maxPayoutBps rises over time (breath arc applied
 *                                      to the ceiling, not the rate). Progressive release.
 *           V4  Compounding Floor   -- Floor earns yield (Aave). The eternal minimum
 *                                      grows in absolute terms each week.
 *           V5  Dual-Floor          -- Two floors: player floor (Formulation A) plus
 *                                      investor floor (DormancyWaterfall2T Tier 1).
 *                                      Full capital protection stack.
 *
 *         FORMULATION B VARIANTS (Seed-as-Flow):
 *           V6  Fixed-Rate Flow     -- seedBps fixed. 10% of each pool returns.
 *                                      Prediction-suite standard (see V16 for
 *                                      obligation-backed protocols). Simple, composable.
 *           V7  Governed Flow       -- seedBps owner-adjustable with timelock.
 *                                      Protocol can tune compounding speed.
 *           V8  Declining Flow      -- seedBps decreases over the season.
 *                                      Front-loaded compounding, climactic finale release.
 *           V9  Accelerating Flow   -- seedBps increases over the season.
 *                                      Slow start, fast finish. Pot acceleration.
 *           V10 Conditional Flow    -- seedBps only active above a participation floor.
 *                                      Compounding halts on low-participation draws.
 *           V11 Tiered Flow         -- Different seedBps for different tier prizes.
 *                                      JP miss seeds at higher rate than P4 miss.
 *           V12 Capped Flow         -- seedBps applies until pot reaches a ceiling,
 *                                      then distributions maximise. Pot growth bounded.
 *
 *         HYBRID VARIANTS (A + B composition):
 *           V13 Floor + Flow        -- Formulation A floor with Formulation B flow
 *                                      on top. The pot can never fall below the floor,
 *                                      but also compounds each draw above it.
 *                                      Novel. No known deployed implementation.
 *           V14 Flow-to-Floor       -- Formulation B flow that converts to Formulation A
 *                                      floor at a trigger event (e.g. draw 26 of 52).
 *                                      First half: compounding. Second half: protection.
 *                                      Novel. No known deployed implementation.
 *           V15 Seasonal Inheritance -- Formulation B flow in season 1 rolls into
 *                                      Formulation A floor for season 2. The eternal
 *                                      seed from season 1 becomes the protected minimum
 *                                      for season 2. Novel. No known deployed implementation.
 *           V16 Breathing Seed      -- Formulation B flow whose DISTRIBUTION side is
 *                                      governed by the ADRP solver (BreathEngine).
 *                                      The seed rollover fraction (seedBps) remains a
 *                                      host parameter. What breathes is the rate at
 *                                      which the pot is drawn down each period, which
 *                                      the solver derives from stock, obligation floor,
 *                                      periods remaining and estimated inflow.
 *
 *                                      Host-side policy layer, NOT solver properties.
 *                                      BreathEngine implements none of these; a host
 *                                      that wants them applies them around solve():
 *                                        (1) Per-period movement rail. The rate is
 *                                            capped in how far it may move between
 *                                            consecutive periods. It breathes; it does
 *                                            not lurch.
 *                                        (2) Rate pinned at period open. Participants
 *                                            enter against a known rate; the rate
 *                                            changes between periods only, never
 *                                            mid-period.
 *                                        (3) Optional minimum-rate rail, applied as
 *                                            max(solve(...), railMin). solve() returns
 *                                            0 on structural insolvency and has no rail
 *                                            concept, so a minimum-prize guarantee is
 *                                            the host's to make. The host must also
 *                                            decide whether to RELEASE that rail when
 *                                            the floor is unreachable. BullsEth
 *                                            releases it (v1.14, H-06): distributing at
 *                                            a rail minimum into a collapse spends the
 *                                            capital the floor exists to protect.
 *                                      Implementation: BreathEngine.sol. This library
 *                                      is the taxonomy reference; the mechanism lives
 *                                      there. Suite standard for obligation-backed
 *                                      protocols. Supersedes the static rate (V6), not
 *                                      the floor concept (Formulation A).
 *
 *         ADJACENT VARIANT (outside both formulations):
 *           V17 Liquid Breathing    -- Principal is never locked. The seed is funded
 *                                      entirely from diverted yield rather than from
 *                                      capital flows, so user deposits stay fully
 *                                      withdrawable. Inhale: under stress a larger
 *                                      share of yield routes to the seed and protection
 *                                      builds. Exhale: under stability the seed's yield
 *                                      routes to long-tenure participants. Slower seed
 *                                      growth, no capital lockup.
 *                                      Sits outside Formulations A and B because
 *                                      neither a floor on the pot nor a fraction of
 *                                      each pool is involved; only yield is. Distinct
 *                                      from V4 Compounding Floor: V4 is a floor that
 *                                      earns yield, V17 is a seed made of yield.
 *                                      HISTORY: published as "Variant 16: Breathing
 *                                      Seed" in the superseded SeedEngine.sol reference
 *                                      repo. Renumbered here because it is a distinct
 *                                      mechanism from the ADRP-governed V16 above and
 *                                      the two must not share a name or a number.
 *                                      Specification only. No implementation.
 *
 * @dev    CHANGELOG
 *
 *         v1.0 -- Initial delivery. Canonical taxonomy and reference
 *                 implementation extracted from the DYBL suite.
 *
 *         v1.1 -- Audit findings resolved.
 *                 Added PARAMETER CONSTRAINT section documenting payoutBps and
 *                 maxPayoutBps must be <= BPS_DENOM. Solidity 0.8.x revert behaviour
 *                 on overflow is the safety net; host must validate at construction.
 *                 Companion whitepaper recommendation noted for variant taxonomy.
 *
 *         v1.2 -- (No changes from v1.1. Version tag only.)
 *
 *         v1.3 -- Semantic accuracy pass.
 *                 "Permanent" and "never" language removed from three locations:
 *                 the notice description, the Formulation A TWO FORMULATIONS block, and
 *                 seedFloor()'s dev and return tags. Replaced with "season-locked"
 *                 and explicit acknowledgement that defined exit paths exist at
 *                 settlement and dormancy. WHAT "ETERNAL" MEANS block added to
 *                 the notice, to disambiguate the name for auditors and integrators.
 *                 No bytecode changes. Pure NatSpec / documentation pass.
 *
 *         v1.4 -- NatSpec audit pass. No bytecode changes.
 *                 L-01: seedFloor() redocumented. It moves with payoutBps and is
 *                 not the invariant floor. FORMULATION A SEMANTICS block added
 *                 defining both floors; invariant floor is obtained via
 *                 seedFloor(pot, 0, maxPayoutBps).
 *                 I-01: unqualified "never" removed from maxDistributable()'s dev block
 *                 (fourth location, missed by the v1.3 pass).
 *                 I-02: out-of-range behaviour restated accurately. Formulation A
 *                 reverts via checked arithmetic; Formulation B clamps.
 *                 I-03: projectedSeedContribution() direction-of-error claim
 *                 corrected. Conservative only when net inflows are non-negative.
 *                 I-04: rounding direction documented as deliberate (seed rounds
 *                 down, dust accrues to distribution).
 *                 V16 entry completed with bounds spec (immutable minimum,
 *                 per-draw rail, pin at draw open); implementation reference
 *                 to BreathEngine.sol. Complementarity note added to TWO
 *                 FORMULATIONS. Em-dashes removed per house style.
 *
 *         v1.5 -- Accuracy pass. No bytecode changes.
 *                 ES-01: the single-fraction closed forms printed for seedFloor(),
 *                 the invariant floor and distributable() are not equivalent to what
 *                 the library computes. Integer division truncates the subtrahend, so
 *                 each closed form returns up to 1 wei less than the subtraction form,
 *                 and in distributable() the closed form broke the file's own
 *                 conservation invariant (seedReturn + distributable == weeklyPool).
 *                 All three restated in subtraction form; ROUNDING (Formulation A)
 *                 block added; integrators directed to call seedFloor(pot, 0, max)
 *                 rather than reimplement the fraction.
 *                 ES-02: V16 conflated the seed rollover rate with the distribution
 *                 rate. Rewritten: the seed fraction is a host parameter, the
 *                 distribution rate is what the solver moves. The three bounds are
 *                 restated as host-side policy rather than solver properties, and the
 *                 minimum-rail entry now records that BullsEth RELEASES the rail below
 *                 the floor (v1.14, H-06) instead of implying an unconditional minimum.
 *                 RE-01: V17 Liquid Breathing added. The superseded SeedEngine.sol
 *                 reference repo published a different mechanism as "Variant 16:
 *                 Breathing Seed"; it is renumbered here so the two never share a name.
 *                 Taxonomy heading updated to seventeen.
 *                 ES-03 (carried from the v1.4 review, outside the step 1 brief):
 *                 V6's unqualified "Suite standard" scoped to the prediction suite so
 *                 it no longer competes with V16's claim; the out-of-range paragraph
 *                 gains the third case (maxPayoutBps > BPS_DENOM with valid ordering,
 *                 which neither reverts nor clamps); seedReturn()'s rounding block
 *                 labelled Formulation B to pair with the new Formulation A block.
 *
 *         v1.6 -- Delta pass on v1.5. No bytecode changes.
 *                 ES-04. Problem: the v1.5 ROUNDING insert split the seedFloor bullet
 *                 from its description, stranding a subjectless paragraph.
 *                 Solution: description moved back under the bullet.
 *                 ES-05. Problem: "= invariant floor plus the fraction at the current
 *                 rate" printed as exact; the decomposition is off by up to 1 wei.
 *                 Solution: qualified, subtraction form named as the definition.
 *                 ES-06. Problem: the third out-of-range case claimed seedFloor()
 *                 surfaces it; it does so only when the delta also exceeds BPS_DENOM.
 *                 Solution: subcase stated, no backstop acknowledged.
 *                 ES-07. Problem: distributable()'s seedBps >= BPS_DENOM guard is
 *                 redundant (seedReturn clamps first) and undocumented.
 *                 Solution: recorded as deliberate redundancy for legibility.
 *                 ES-08. Problem: projectedSeedContribution()'s seed * draws is an
 *                 unbounded multiplication with no overflow note.
 *                 Solution: overflow sentence added; reverts, tooling only.
 *                 Also: "up to 1 wei" tightened to "exactly 1 wei" where the gap is
 *                 provably exactly 1 (closed form vs subtraction form). Left as "up
 *                 to" in ES-05, where 0 or 1 both occur.
 *
 *         v1.7 -- Delta pass on v1.6. No bytecode changes.
 *                 ES-09. Problem: V16 sits under HYBRID VARIANTS but the hybrid range
 *                 was written V13 to V15, excluding a member of its own group.
 *                 Solution: range extended to V16, with the composition stated
 *                 precisely: V16's floor is an absolute host-supplied obligation, not
 *                 a proportional pot fraction, anchored to the Formulation A invariant
 *                 floor when the host sets it to seedFloor(pot, 0, maxPayoutBps).
 *                 ES-10. Problem: the taxonomy intro still called V6 the suite
 *                 standard after v1.5 scoped V6's own entry to the prediction suite.
 *                 Solution: intro scoped to match, V16 named for obligation-backed.
 *                 Cosmetic. Problem: two line-wrap artifacts from the v1.5 and v1.6
 *                 insertions (seedReturn ROUNDING block, taxonomy intro).
 *                 Solution: reflowed.
 *                 Pre-publication amendments within v1.7 (ES-11 to ES-13):
 *                 ES-11. Problem: the "exactly 1" justification read "a non-integral
 *                 quotient differs from its ceiling by exactly 1", conflating the
 *                 real quotient (which differs from its ceiling by less than 1) with
 *                 its floor. Solution: restated as the floor and ceiling of a
 *                 non-integral quotient differing by exactly 1.
 *                 ES-12. Problem: the large-delta backstop claimed the result
 *                 "exceeds pot and seedFloor() underflows"; false for dust pots
 *                 (pot 1, delta 10001: maxDistributable 1, seedFloor 0, silent).
 *                 Solution: scoped with the counterexample printed; "no backstop"
 *                 widened to those subcases. Superseded within v1.7 by ES-14.
 *                 ES-14. Problem: ES-12's replacement scoping, "surfaced only when
 *                 the delta exceeds BPS_DENOM AND the pot holds at least BPS_DENOM
 *                 wei", states a SUFFICIENT condition as a NECESSARY one. A pot below
 *                 BPS_DENOM wei still reverts at a large enough delta (pot 5000,
 *                 delta 20001: maxDistributable returns 10000, exceeding pot), so the
 *                 paragraph promised silence where the library in fact reverts.
 *                 Solution: replaced with the exact condition, delta > BPS_DENOM AND
 *                 pot * (delta - BPS_DENOM) >= BPS_DENOM, verified by exhaustive
 *                 enumeration against actual behaviour; both silent families kept as
 *                 illustrations and the joint dependence stated explicitly.
 *                 ES-13. Problem: "becomes a literal Formulation A composition"
 *                 overstated -- the protected VALUE coincides at the moment of the
 *                 call, the MECHANISM does not (V16 enforces at maturity,
 *                 Formulation A caps per period, proportionally, as the pot moves).
 *                 Solution: reworded to "anchors it to the Formulation A invariant
 *                 floor as valued at the moment of the call", here and in the ES-09
 *                 entry above.
 *                 ES-15. Problem: seedFloor()'s dev block carried the line "See
 *                 FORMULATION A SEMANTICS in the library header" twice consecutively,
 *                 an amendment-landing artifact of the same class as ES-04. Present in
 *                 one lineage copy only, which is why it is recorded here rather than
 *                 passing unnoticed as drift. Solution: duplicate removed.
 *                 ES-16. Problem: four changelog lines wrote NatSpec tag names as
 *                 prose. Two of them sat at line-initial position, where Solidity
 *                 parses them as real tags: the generated user documentation for this
 *                 library already contained changelog fragments spliced into its
 *                 notice text, visible in solc --userdoc output. A present defect, not
 *                 a future hazard. Solution: tag names written without the leading
 *                 at-sign throughout. Rule for this suite: never write a literal tag
 *                 inside a doc comment.
 *                 ES-17. Problem: V16 said the solver "guarantees the maturity pot".
 *                 BreathEngine's own documentation says its floor guarantee is exact
 *                 with respect to its projection model and can diverge from a host
 *                 whose arithmetic differs. Two files in one library disagreeing.
 *                 Solution: reworded to "holds the maturity pot to the floor it is
 *                 given".
 *                 ES-18. Problem: "Origin: suite standard from v1.6 onward" reads as
 *                 self-referential now this file has its own v1.6.
 *                 Solution: qualified as a suite contract version.
 *                 Dates removed from this changelog: they were inaccurate, and they
 *                 had already been removed from the standalone changelog, leaving the
 *                 two out of step.
 */
library EternalSeed {

    uint256 internal constant BPS_DENOM = 10_000;

    // ─────────────────────────────────────────────────────────────────────────
    // FORMULATION A: SEED-AS-FLOOR
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the remaining distributable headroom above the current rate
     *         under Formulation A.
     *
     * @dev    The pot has a season-locked floor: a fraction cannot be distributed
     *         for the duration of the season.
     *         maxDistributable = pot * (maxPayoutBps - payoutBps) / BPS_DENOM
     *
     *         This is the ADDITIONAL amount that could still be scheduled for
     *         distribution this period by raising payoutBps to its ceiling. It is
     *         not the amount payable at the current rate; that quantity is
     *         pot * payoutBps / BPS_DENOM and is computed by the host.
     *
     *         REQUIRES: payoutBps <= maxPayoutBps <= BPS_DENOM.
     *         If payoutBps > maxPayoutBps: underflow, reverts in 0.8.x.
     *         If maxPayoutBps > BPS_DENOM: result may exceed pot. Validate at host.
     *
     * @param  pot           Current pot size.
     * @param  payoutBps     Current committed distribution rate in BPS. Must be
     *                       <= maxPayoutBps.
     * @param  maxPayoutBps  Maximum ever-distributable fraction in BPS. Must be <= 10000.
     * @return maxDist       Remaining distribution headroom this period.
     */
    function maxDistributable(
        uint256 pot,
        uint256 payoutBps,
        uint256 maxPayoutBps
    ) internal pure returns (uint256 maxDist) {
        return pot * (maxPayoutBps - payoutBps) / BPS_DENOM;
    }

    /**
     * @notice Returns the pot balance beyond remaining distribution headroom
     *         under Formulation A.
     *
     * @dev    seedFloor = pot - maxDistributable(pot, payoutBps, maxPayoutBps)
     *                   = pot - pot * (maxPayoutBps - payoutBps) / BPS_DENOM
     *
     *         The subtraction form above is exact. The single-fraction closed form
     *         pot * (BPS_DENOM - maxPayoutBps + payoutBps) / BPS_DENOM is NOT
     *         equivalent and returns exactly 1 wei less whenever the product is not a
     *         multiple of BPS_DENOM. See ROUNDING (Formulation A) in the library header.
     *
     *         WARNING: this value moves with payoutBps and is NOT the
     *         season-invariant protected minimum. For the invariant floor (the
     *         amount no governance action can distribute during the season) call
     *         seedFloor(pot, 0, maxPayoutBps), which equals
     *         pot - pot * maxPayoutBps / BPS_DENOM. Call the function; do not
     *         reimplement the fraction (ROUNDING, Formulation A).
     *         See FORMULATION A SEMANTICS in the library header.
     *
     *         The invariant floor compounds via Aave in production. Released
     *         through defined exit paths at settlement or dormancy. Season-locked,
     *         not irrevocable.
     *
     *         REQUIRES: payoutBps <= maxPayoutBps <= BPS_DENOM.
     *         Same overflow preconditions as maxDistributable().
     *
     * @param  pot           Current pot size.
     * @param  payoutBps     Current committed distribution rate in BPS.
     * @param  maxPayoutBps  Maximum ever-distributable fraction in BPS.
     * @return floor         Pot balance not reachable by further rate increases
     *                       this period. Pass payoutBps = 0 for the season-invariant
     *                       floor. Released at settlement or dormancy.
     */
    function seedFloor(
        uint256 pot,
        uint256 payoutBps,
        uint256 maxPayoutBps
    ) internal pure returns (uint256 floor) {
        return pot - maxDistributable(pot, payoutBps, maxPayoutBps);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FORMULATION B: SEED-AS-FLOW
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Returns the seed amount that rolls back into the pot (Formulation B).
     *
     * @dev    seed = weeklyPool * seedBps / BPS_DENOM
     *
     *         This amount is withheld from distribution and returned to the pot
     *         after the draw resolves. It is the compounding engine of the suite.
     *         At seedBps = 1000 (10%), the pot grows draw-on-draw through the season.
     *
     *         ROUNDING (Formulation B, deliberate): seed rounds down; distributable()
     *         takes the exact remainder, so seedReturn + distributable == weeklyPool
     *         always.
     *         Conservation is exact by construction. Dust (at most 1 wei per draw)
     *         accrues to distribution, not the seed. Rounding favours players.
     *
     *         REQUIRES: seedBps <= BPS_DENOM. If seedBps > BPS_DENOM, the naive
     *         formula would return more than weeklyPool, violating conservation.
     *         The boundary clamp below prevents this. Validate at host constructor.
     *
     *         Special case: seedBps >= BPS_DENOM returns weeklyPool (entire pool seeds,
     *         zero distributable). This is the conservative limit case and is safe
     *         because distributable() = weeklyPool - seedReturn() = 0 in this case.
     *
     * @param  weeklyPool  Total prize pool for this draw.
     * @param  seedBps     Rollover fraction in BPS. Must be <= BPS_DENOM.
     * @return seed        Amount returned to pot after distribution.
     */
    function seedReturn(
        uint256 weeklyPool,
        uint256 seedBps
    ) internal pure returns (uint256 seed) {
        if (seedBps >= BPS_DENOM) return weeklyPool;
        return weeklyPool * seedBps / BPS_DENOM;
    }

    /**
     * @notice Returns the distributable prize amount for this draw (Formulation B).
     *
     * @dev    distributable = weeklyPool - seedReturn(weeklyPool, seedBps)
     *
     *         This is NOT the same as weeklyPool * (BPS_DENOM - seedBps) / BPS_DENOM.
     *         That closed form truncates independently and returns 1 wei less whenever
     *         weeklyPool * seedBps is not a multiple of BPS_DENOM, which BREAKS the
     *         conservation invariant stated below. Worked example: weeklyPool = 10001,
     *         seedBps = 1000. This function returns 9001 and seedReturn() returns 1000,
     *         summing to exactly 10001. The closed form returns 9000, summing to 10000
     *         and losing a wei. Conservation holds only for the subtraction form.
     *
     *         ROUNDING: takes the exact remainder after seedReturn(), so the
     *         conservation invariant seedReturn + distributable == weeklyPool
     *         holds exactly. See seedReturn() ROUNDING note.
     *
     *         REQUIRES: seedBps <= BPS_DENOM.
     *
     *         At seedBps >= BPS_DENOM: returns 0 (entire pool seeds back).
     *         This is the correct conservative limit. The guard is DELIBERATE
     *         REDUNDANCY, not a required branch: seedReturn() already clamps to
     *         weeklyPool, so the subtraction alone yields 0. It is kept so the limit
     *         case is legible at the call site rather than inferred from the callee.
     *
     * @param  weeklyPool  Total prize pool for this draw.
     * @param  seedBps     Rollover fraction in BPS. Must be <= BPS_DENOM.
     * @return dist        Amount available for prize distribution this draw.
     */
    function distributable(
        uint256 weeklyPool,
        uint256 seedBps
    ) internal pure returns (uint256 dist) {
        if (seedBps >= BPS_DENOM) return 0;
        return weeklyPool - seedReturn(weeklyPool, seedBps);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TOOLING HELPER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @notice Projects the cumulative seed contribution to the pot over N draws.
     *
     * @dev    LINEAR APPROXIMATION ONLY. Assumes constant breathBps and seedBps
     *         across all draws, and ignores compounding (i.e. the pot is treated
     *         as constant across the projection horizon).
     *
     *         DIRECTION OF ERROR: conditional. weeklyPool is exhaled from the pot
     *         itself, so the pot only grows across draws when net inflows plus
     *         yield exceed net exhale. When they do, the true cumulative seed
     *         exceeds this estimate (conservative underestimate). Under zero or
     *         negative net inflows the pot shrinks each draw and this figure is
     *         an UPPER bound instead. Do not treat the linear estimate as a floor
     *         without checking the inflow assumption.
     *
     *         Use for governance calibration and dashboard display only.
     *         Do not use for solvency decisions; use BreathEngine.sim() instead.
     *
     *         REQUIRES: breathBps <= BPS_DENOM, seedBps <= BPS_DENOM.
     *
     *         OVERFLOW: draws is unbounded and seed * draws is a multiplication, so
     *         pathological inputs revert under 0.8.x checked arithmetic rather than
     *         corrupting. Unreachable at realistic magnitudes, and this is a tooling
     *         function with no funds path, so the revert is the whole exposure.
     *
     * @param  pot       Current pot size (held constant across projection).
     * @param  breathBps Distribution rate in BPS. Must be <= BPS_DENOM.
     * @param  seedBps   Rollover fraction in BPS. Must be <= BPS_DENOM.
     * @param  draws     Number of draws to project.
     * @return contrib   Estimated cumulative seed returned to pot over N draws.
     */
    function projectedSeedContribution(
        uint256 pot,
        uint256 breathBps,
        uint256 seedBps,
        uint256 draws
    ) internal pure returns (uint256 contrib) {
        uint256 weeklyPool = pot * breathBps / BPS_DENOM;
        uint256 seed       = seedReturn(weeklyPool, seedBps);
        return seed * draws;
    }
}
