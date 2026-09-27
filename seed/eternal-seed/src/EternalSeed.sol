// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1
// Licensor:       DYBL Foundation
// Licensed Work:  EternalSeed.sol
// Change Date:    1 February 2030
// Change License: MIT

pragma solidity ^0.8.24;

/**
 * @title  EternalSeed
 * @author DYBL Foundation
 * @notice Protect it, grow it, pace it.
 *
 *         The Eternal Seed is the pot itself, under a rule that stops it emptying. It is
 *         not a reserve held to one side. A game collects money from its players, and the
 *         seed is that money together with the rule deciding how much of it may leave each
 *         period. Hold something back and the next period does not start from zero.
 *
 *         This file is the reference for that rule: four short functions that state it
 *         exactly, a projection helper, and a map of the ways the rule has been used. The
 *         functions are internal, so a host compiles them in rather than calling a deployed
 *         copy, and the hosts in this suite write their own one-line version of the rule
 *         instead. They are meant to share its behaviour. The test suite beside this file
 *         pins the reference's behaviour and checks a copy of each host's line against it;
 *         known differences are listed in KNOWN_ISSUES.md.
 *
 *         WHAT "ETERNAL" MEANS
 *
 *         Eternal describes the pot, not an amount. The name came from the growth: a
 *         lottery that keeps a share back every week starts the next week above zero, so
 *         the pot compounds instead of resetting. It was never a claim that some balance
 *         sits untouchable forever. Whether a pot can literally be eternal is a question
 *         the hosts answer differently, and one of them answers no. See ENDINGS.
 *
 * @dev    TWO AXES
 *
 *         Earlier versions of this file listed seventeen numbered variants. Most were one
 *         mechanism at a different setting, and the numbering collided with a superseded
 *         reference repository that used the same numbers for different mechanisms. The
 *         design space is described better by two independent questions.
 *
 *         RETENTION asks how money is held back. Two answers: Floor and Flow.
 *         ENDING asks what the held-back money is for and where it finishes. Four answers:
 *         Compound, Port, Spend-down and Return.
 *
 *         Any retention rule can carry any ending. The suite has moved along the ending
 *         axis while retention stood still, which is why the old list kept filing endings
 *         as retention variants and never sat right.
 *
 * @dev    RETENTION: FLOOR (FORMULATION A)
 *
 *         A fraction of the pot cannot be distributed while the game or season runs. It
 *         stays in the pot, earning yield where the host supplies it to a lender, and is
 *         released through the host's defined exits. This was the first form of the idea.
 *         Functions: maxDistributable(), seedFloor().
 *
 *         CEILING POLICY. The ceiling maxPayoutBps may be fixed at deployment, adjustable
 *         by an owner within a committed maximum, or scheduled to rise over time. Each
 *         changes who may move the ceiling and how fast; none changes the mechanism.
 *         The suite's SeedRelease library, separate from this one, implements a bounded
 *         ratchet for the adjustable case.
 *
 * @dev    FORMULATION A SEMANTICS (payoutBps AND THE TWO FLOORS)
 *
 *         payoutBps is the distribution rate currently committed by the host,
 *         governed within [0, maxPayoutBps] (see CEILING POLICY). maxPayoutBps is the season
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
 * @dev    RETENTION: FLOW (FORMULATION B)
 *
 *         A share of each prize returns to the pot instead of being paid out, so the pot
 *         compounds period on period. The seed here is not a floor; it is an engine.
 *         Functions: seedReturn(), distributable().
 *
 *         RATE POLICY. The returning share seedBps may be fixed, adjustable under a
 *         timelock, scheduled to fall or rise across a season, gated on participation,
 *         set per prize tier, or suspended once the pot reaches a ceiling. Each is the
 *         same mechanism on a different schedule.
 *
 *         WHAT ACTUALLY RETURNS. seedBps is not the whole of it. When a top prize goes
 *         unwon, some of that prize also comes back to the pot, so the true returning
 *         share is the reseed plus the routed part of missed prizes. Measuring it from
 *         money flows misleads, because a rolled jackpot looks permanently retained until
 *         somebody wins it; counting how often prizes are missed does not. Two host shapes
 *         call for two answers, and both are correct:
 *           A perpetual host has no end date to re-anchor against, so it measures the
 *           miss rate as it runs. Lettery Perpetual does this through Rho.sol, where the
 *           returning share is reseed + jackpotShare * missToPot * missRate.
 *           A season host knows its routing at deployment and sizes every draw from the
 *           pot it actually holds, so it can compute the share once, at the miss-always
 *           limit, and any error does not carry forward. In Lettery TF this is RETURN_BPS:
 *           the 20% reseed withheld from every prize, plus 30% of the jackpot tier's share
 *           of a prize when the jackpot is missed. At the shipped split that is 20 points
 *           plus 9.9 points, 29.9% in all. It leaves out money a draw returns on its own:
 *           a bottom tier nobody wins, a tier too thin to pay and rounding dust all go
 *           back to the pot, so the forecast sits on the low side.
 *
 * @dev    ENDINGS: WHAT THE SEED IS FOR
 *
 *         COMPOUND. The pot has no end date, so the seed's job is to keep it growing and
 *         the payout rule must be affordable indefinitely. Lettery Perpetual.
 *
 *         PORT. What accumulates in one season becomes the opening position of the next,
 *         so a season's players are funding the next season rather than losing their
 *         contribution at the close. Specified, not yet built.
 *
 *         SPEND-DOWN. The pot is aimed at zero by a known last draw, with the largest
 *         payments near the end. SeedTogether, where the seed and the tank being spent are
 *         one balance.
 *
 *         RETURN. The season ends on a known draw, and what the season did not pay out as
 *         prizes is handed back to those who funded it: per ticket in Lettery TF, by
 *         seniority in BullsEthCRE. BullsEthCRE's order is the investor's unreleased seed
 *         first, then committed players up to their promised return, with anything above
 *         that going to the treasury (all of it, if no committed player qualifies). Its
 *         sizing solver holds the pot above that obligation to the last draw, and the last
 *         draw pays out everything above it.
 *
 *         BALLAST. In the Spend-down and Return rows the seed's job changes. It is not
 *         growing the pot toward an open future; it is holding the shape of a pot being
 *         spent on purpose, so that the season reaches its last draws with the largest
 *         payments still ahead of it. The sizing solver treats the returning share as
 *         known and aims through it (SeasonArc's returnBps input).
 *
 *         THREE ANSWERS TO "ETERNAL". Lettery Perpetual never ends, so its pot is eternal
 *         in the plain sense. The port carries a pot across a boundary, so it is eternal
 *         by becoming the next one. SeedTogether and Lettery TF end on a date and hand the
 *         pot back, which is not eternal at all, deliberately. The name came from the
 *         first idea; the hosts are where it was tested.
 *
 * @dev    THE GRID
 *
 *         Retention across, ending down. Each cell names the host that runs it, or says
 *         why it is empty.
 *
 *                        FLOOR                          FLOW
 *         COMPOUND       the original idea               Lettery Perpetual
 *         PORT           open                            specified, see COMPOSITIONS
 *         SPEND-DOWN     open, see below                 SeedTogether
 *         RETURN         open                            Lettery TF, BullsEthCRE
 *
 *         Floor with Spend-down has no known implementation: a protected minimum that is
 *         itself scheduled to be spent into a finale, so that even the untouchable part of
 *         the pot carries a maturity date. It is recorded because a taxonomy that predicts
 *         an unbuilt cell is doing its job. Whether it is a product or a curiosity is open.
 *
 * @dev    COMPOSITIONS
 *
 *         Retention rules combine. The first three below are novel to this suite and have
 *         no known deployed implementation elsewhere.
 *
 *         FLOOR PLUS FLOW. A floor with a flow above it. The pot does not fall below the
 *         floor, and also compounds each draw above it.
 *
 *         FLOW TO FLOOR. A flow that converts to a floor at a trigger, for example the
 *         midpoint of a season. Compounding first, protection after.
 *
 *         SEASONAL INHERITANCE. A flow in one season that becomes the protected floor of
 *         the next. The Port ending expressed as a composition. The grid files it under
 *         Flow because that is the rule running while the season does; it lands as a
 *         Floor in the season after.
 *
 *         DUAL FLOOR. Two floors for two classes of capital, a player floor and an investor
 *         floor. Meaningful only where more than one class of money is in the pot; with one
 *         class it collapses to an ordinary floor. See the suite's DormancyWaterfall2T
 *         library, and its specified three-tier sibling.
 *
 *         ADJACENT: YIELD-FUNDED SEED. Principal is not locked. The seed is funded only
 *         from diverted yield, so deposits stay withdrawable: under stress more yield
 *         routes to the seed, under stability the seed's yield routes to long-standing
 *         participants. It sits outside both retention rules because neither a floor on
 *         the pot nor a share of each prize is involved, only yield. It differs from a
 *         floor that earns yield: that is a floor which earns, this is a seed made of
 *         earnings. Specified, not built. The superseded reference repository published
 *         this mechanism as its "Variant 16"; it is named here by what it does so that it
 *         cannot be confused with anything numbered in that repository.
 *
 * @dev    SIZING SOLVERS
 *
 *         Every seed needs an answer to a separate question: what does this period pay?
 *         That question is the Autonomous Distribution Rate Problem, and it is answered in
 *         other files, not this one. There are four solvers, each for a different ending
 *         condition:
 *
 *           Hold a floor to a deadline          BreathEngine.sol, first host BullsEthCRE
 *           Sustain with no end                 Breath.sol, first host Lettery Perpetual
 *           Spend to zero in equal shares       SeedGlide, inline in SeedTogether
 *           Spend down on a rising arc          SeasonArc.sol, first host Lettery TF
 *
 *         Lettery TF sits in the grid's Return row: the arc spends its prize pot down, and
 *         what the seed held back is handed back per ticket at the close.
 *
 *         For a game that spends its pot down by a date, the choice between the two
 *         spend-down solvers is decided by where its prize money comes from. A pot funded
 *         by yield on parked deposits can open with a tiny first payment, because nobody
 *         paid an entry price that the payment has to justify, so equal shares work. A pot
 *         funded by ticket sales is different: the smallest prize is meant to be worth more
 *         than the ticket from the first draw, and equal shares from a small early pot do
 *         not manage that, so the payment grows from a solved opening instead. Parked yield
 *         permits a glide. Ticket money needs an arc.
 *
 * @dev    LINEAGE
 *
 *         The question was how to make the pot bigger. The first answer was to keep part
 *         of it back, a floor that was never paid out. Then a share of every prize coming
 *         home, so the pot grew draw on draw. Then putting the money held back to work,
 *         earning while it waited and drawn back when needed. Held back as a floor or
 *         returned as a share of each prize, how large the pot gets is set by income, yield
 *         and what each draw pays. Either way the pot can become large, and most of what
 *         followed answers the question that raised: what should a large pot actually do.
 *         The sizing solvers, the endings and the protections all come from there. The
 *         mechanism barely changed; what it was for did.
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
 *         Version history for this file is kept in its changelog, not here.
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
     * @dev    A fraction of the pot cannot be distributed while the game or season
     *         runs.
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
     *         The invariant floor stays in the pot, earning yield where the host
     *         supplies it to a lender, and leaves through the host's defined exits.
     *
     *         REQUIRES: payoutBps <= maxPayoutBps <= BPS_DENOM.
     *         Same overflow preconditions as maxDistributable().
     *
     * @param  pot           Current pot size.
     * @param  payoutBps     Current committed distribution rate in BPS.
     * @param  maxPayoutBps  Maximum ever-distributable fraction in BPS.
     * @return floor         Pot balance not reachable by further rate increases
     *                       this period. Pass payoutBps = 0 for the season-invariant
     *                       floor. Released through the host's defined exits.
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
     *         At seedBps = 1000 (10%) a tenth of every pool comes back, so the next draw
     *         does not start from zero.
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
     * @dev    LINEAR APPROXIMATION ONLY. Assumes constant payoutBps and seedBps
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
     *         REQUIRES: payoutBps <= BPS_DENOM, seedBps <= BPS_DENOM.
     *
     *         OVERFLOW: draws is unbounded and seed * draws is a multiplication, so
     *         pathological inputs revert under 0.8.x checked arithmetic rather than
     *         corrupting. Unreachable at realistic magnitudes, and this is a tooling
     *         function with no funds path, so the revert is the whole exposure.
     *
     * @param  pot       Current pot size (held constant across projection).
     * @param  payoutBps Distribution rate in BPS. Must be <= BPS_DENOM.
     * @param  seedBps   Rollover fraction in BPS. Must be <= BPS_DENOM.
     * @param  draws     Number of draws to project.
     * @return contrib   Estimated cumulative seed returned to pot over N draws.
     */
    function projectedSeedContribution(
        uint256 pot,
        uint256 payoutBps,
        uint256 seedBps,
        uint256 draws
    ) internal pure returns (uint256 contrib) {
        uint256 weeklyPool = pot * payoutBps / BPS_DENOM;
        uint256 seed       = seedReturn(weeklyPool, seedBps);
        return seed * draws;
    }
}
