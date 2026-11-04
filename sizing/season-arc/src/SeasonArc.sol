// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1
// Change Date: 1 February 2030. On the Change Date, available under MIT.
pragma solidity 0.8.24;

/**
 * @title  SeasonArc
 * @notice Paced, autonomous distribution from a fixed-term pot. Sizes each draw of a season
 *         with a known last draw: the first draw pays a set share of the pot, each later draw
 *         pays the last payment times a growth factor solved fresh every draw so the pot is
 *         spent by the last draw, and the last draw pays the whole pot.
 *
 * @dev    The reasoning behind each rule, the designs it replaced, and where each claim is
 *         tested are in DESIGN.md beside this file. Comments here keep only what a reader of
 *         the code needs: what each part does, and the traps.
 *
 * @dev    Pure: reads and writes no storage. `size` is external, so a host links one
 *         deployed copy and reaches it by DELEGATECALL. A host cannot be re-pointed after
 *         deploy, so the address it links is part of what that host is (KNOWN_ISSUES).
 *         The library returns an amount; tiers, withholding and payment are the host's.
 */
library SeasonArc {

    /// @notice A payment must return less than it costs, or the search walks the wrong way.
    error BadReturnShare();
    /// @notice The opening share cannot exceed the whole pot. Named for the library rather
    ///         than after any host's own opening-share check, which may be narrower.
    error OpeningShareTooLarge();

    uint256 internal constant BPS = 10_000;

    /// @dev Growth factors are per-draw multipliers in BPS; 10_000 is flat.
    uint256 internal constant G_MIN = 10_000;
    /// @dev THE TOP OF THE SEARCH, NOT A SAFETY RAIL. Do not lower it: the forward walk already
    ///      rejects any candidate the pot cannot carry, and a ceiling at a doubling can return
    ///      itself rather than the solved answer when a crowd arrives mid-season.
    uint256 internal constant G_MAX = 1_000_000;
    /// @dev Bisection steps. The loop closes in about twenty and breaks early; 48 is headroom.
    uint256 internal constant ITERS = 48;

    enum Bind {
        OPENING,    // first draw of the season: a share of the pot
        ARC,        // the solved growth factor
        SUSTAINED,  // the arc bottomed out: the largest flat payment the season can carry,
                    // which can be zero on a pot too small to carry one unit a draw
        POT,        // nothing to size from: an empty pot, or no draws remaining
        CLOSING     // the last draw takes everything left
    }

    /**
     * @notice What this draw should pay.
     * @param  pot           The prize pot, AFTER this draw's income and yield have landed.
     * @param  lastPaid      What the previous draw paid. Zero on the first draw of a season.
     * @param  drawsLeft     Draws remaining INCLUDING this one. One means the closing draw.
     * @param  incomeEstimate The income the solver assumes will arrive on each remaining
     *         draw. The host passes what it just observed; a season that grows or shrinks is
     *         corrected on the next draw rather than predicted here.
     * @param  returnBps     Share of each sized prize that comes back to the pot instead of
     *         leaving (for example a reseed, or the part of a missed jackpot that goes home).
     *         Under-stating it makes the arc shallower, and the money the solver did not
     *         expect builds up and is paid in one step on the closing draw.
     * @param  openingBps    Share of the pot the first draw pays. The season's only dial.
     * @return amount        What to pay.
     * @return bind          Which rule decided it.
     */
    function size(
        uint256 pot,
        uint256 lastPaid,
        uint256 drawsLeft,
        uint256 incomeEstimate,
        uint256 returnBps,
        uint256 openingBps
    ) external pure returns (uint256 amount, Bind bind) {
        // The solve rests on these. At returnBps >= BPS a steeper arc would leave MORE behind
        // and the bisection would walk the wrong way; neither mistake is visible downstream.
        if (returnBps >= BPS) revert BadReturnShare();
        if (openingBps > BPS) revert OpeningShareTooLarge();
        if (drawsLeft == 0) return (0, Bind.POT);

        // ORDER MATTERS: the closing draw is answered before the empty pot, so an empty pot on
        // the last draw reports CLOSING, not POT. A host acts on the bind, and one that refuses
        // a POT draw could otherwise never end its season.
        if (drawsLeft == 1) return (pot, Bind.CLOSING);

        if (pot == 0) return (0, Bind.POT);

        // The opening: a share of the pot. No clamp needed, because openingBps <= BPS is
        // checked above.
        if (lastPaid == 0) {
            return ((pot * openingBps) / BPS, Bind.OPENING);
        }

        uint256 g = _solve(pot, lastPaid, drawsLeft, incomeEstimate, returnBps);
        amount = (lastPaid * g) / BPS;

        // THE SOLVER'S FLOOR MEANS ONE OF TWO THINGS. It returns G_MIN both when flat runs the
        // pot dry and when flat fits but nothing steeper does. So the walk is asked once more at
        // flat: if flat leaves anything, the arc has flattened and this draw pays the last
        // amount (ARC). Only if flat runs dry does the fallback pay (SUSTAINED).
        //
        // DO NOT REGATE THIS ON `amount < equalShare`. A healthy arc pays less than an equal
        // share early by design, and a draining pot has lastPaid above the equal share, so
        // that gate fires in the wrong case and misses the right one. DESIGN.md has the rest.
        if (g == G_MIN) {
            if (_leftover(pot, lastPaid, drawsLeft, incomeEstimate, returnBps, G_MIN) > 0) {
                return (amount, Bind.ARC);
            }
            return (_maxSustainable(pot, drawsLeft, incomeEstimate, returnBps), Bind.SUSTAINED);
        }

        // No cap against the pot: any g above G_MIN was accepted only where the forward walk,
        // which rejects a payment at or above the pot, left something over.
        return (amount, Bind.ARC);
    }

    /// @dev Bisects for the steepest growth factor that still leaves something at the close.
    ///      The leftover falls as g rises (while returnBps < BPS), so bisection applies.
    function _solve(
        uint256 pot,
        uint256 lastPaid,
        uint256 drawsLeft,
        uint256 incomeEstimate,
        uint256 returnBps
    ) private pure returns (uint256) {
        uint256 lo = G_MIN;
        uint256 hi = G_MAX;
        for (uint256 i = 0; i < ITERS; i++) {
            uint256 mid = (lo + hi) / 2;
            if (_leftover(pot, lastPaid, drawsLeft, incomeEstimate, returnBps, mid) > 0) {
                lo = mid;          // too shallow: money would be stranded
            } else {
                hi = mid;          // too steep: the pot runs out before the last draw
            }
            if (hi - lo <= 1) break;
        }
        return lo;
    }

    /// @notice The largest FLAT payment the pot and its future income can carry to the close.
    /// @dev    With flat payments P, the balance before draw k is
    ///
    ///             p(k) = pot + k*incomeEstimate - k*P*(BPS - returnBps)/BPS
    ///
    ///         and the walk survives draw k when P < p(k), that is
    ///
    ///             P  <  BPS * (pot + k*incomeEstimate) / (BPS + k*(BPS - returnBps))
    ///
    ///         The bound is monotone in k, so the tightest sits at k = 0 or k = drawsLeft - 1.
    ///
    ///         THE CORRECTION LOOP IS NOT OPTIONAL. Integer division floors the returned share,
    ///         so the closed form can sit up to drawsLeft units above what the walk survives;
    ///         the loop closes that band and runs only when the first candidate misses.
    ///
    ///         EVIDENCE. sim/arc_fuzz.py checks the Python form of this against a Python
    ///         bisection on 40,000 seeded random cases (zero difference, zero infeasible); that
    ///         does not test this Solidity. The Solidity is tested by
    ///         testFuzz_whateverTheFallbackPaysIsTheMostTheWalkSurvives and three pinned tests
    ///         in test/SustainedFallback.t.sol.
    function _maxSustainable(
        uint256 pot,
        uint256 drawsLeft,
        uint256 incomeEstimate,
        uint256 returnBps
    ) private pure returns (uint256) {
        uint256 spend = BPS - returnBps;          // what a payment costs the pot, net of return

        // The two ends. Minus one turns "P < bound" into "P <= this". The minus one would
        // underflow at pot == 0, which size() never passes. The numerator reverts on overflow
        // above roughly 1.15e73 (KNOWN_ISSUES).
        uint256 first = ((BPS * pot) - 1) / BPS;
        uint256 last  = ((BPS * (pot + (drawsLeft - 1) * incomeEstimate)) - 1)
                        / (BPS + (drawsLeft - 1) * spend);
        uint256 cand  = first < last ? first : last;
        if (cand == 0) return 0;

        // The walk, not the algebra, decides.
        if (_leftover(pot, cand, drawsLeft, incomeEstimate, returnBps, G_MIN) > 0) return cand;

        // Bisect the band below it. If the miss were ever wider than the band, the final
        // check returns 0 rather than a payment the walk would reject.
        uint256 lo = cand > drawsLeft + 2 ? cand - drawsLeft - 2 : 0;
        uint256 hi = cand;
        while (hi - lo > 1) {
            uint256 mid = (lo + hi) / 2;
            if (mid > 0 && _leftover(pot, mid, drawsLeft, incomeEstimate, returnBps, G_MIN) > 0) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        if (lo == 0) return 0;
        return _leftover(pot, lo, drawsLeft, incomeEstimate, returnBps, G_MIN) > 0 ? lo : 0;
    }

    /// @dev What the pot would hold after the last remaining draw, if payments grew at `g`.
    ///      This draw's income is already in `pot`; income is added for each later draw.
    ///      Returns 0 as soon as a payment meets or exceeds the balance before it.
    function _leftover(
        uint256 pot,
        uint256 lastPaid,
        uint256 drawsLeft,
        uint256 incomeEstimate,
        uint256 returnBps,
        uint256 g
    ) internal pure returns (uint256) {
        uint256 p = pot;
        uint256 pay = lastPaid;
        for (uint256 k = 0; k < drawsLeft; k++) {
            if (k > 0) p += incomeEstimate;
            pay = (pay * g) / BPS;
            if (pay >= p) return 0;      // ran dry: this g is too steep
            p -= pay;
            // NO RETURN ON THE LAST DRAW, DELIBERATELY. A modelling choice that under-counts
            // the pot by one returned share and leans the arc slightly shallow. Changing it
            // changes what the solver pays for every host (KNOWN_ISSUES).
            // Multiply before dividing, deliberately: dividing first floors returnBps / BPS to
            // zero. A linter may flag this shape; it is correct here.
            if (k + 1 < drawsLeft) p += (pay * returnBps) / BPS;
        }
        return p;
    }
}
