// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1.
// Change Date: 1 February 2030. On the Change Date, available under MIT.

pragma solidity 0.8.24;

/**
 * @title  Breath
 * @notice Decides what a draw can afford to pay, from live state only, for a game with no end
 *         date.
 *
 *         The anchor is BREAKEVEN: the payout that spends recent income (the fast average)
 *         plus this draw's yield, once the share that recycles back to the pot is grossed
 *         up. When this draw's income matches that average, paying below breakeven grows
 *         the pot, paying at it holds the pot, and paying above it draws the pot down.
 *         Every term is something the host already knows, so no target is asserted.
 *
 *         THE POT IS MANAGED FROM OUTSIDE THIS LIBRARY. Breath answers one question each
 *         draw: what can this draw afford. It does not decide when anything happens. A host
 *         channel that wants to spend surplus may ask `spare()` what sits above the cover
 *         target, and may be told zero. A host may instead size its own extra payouts from
 *         the pot and the weekly prize, as the first host, Lettery Perpetual, does; it does
 *         not call `spare()`. Either way no channel can override the weekly sizing. A host
 *         that owns its own surplus rule should not also rely on `spare()`, or one rule has
 *         two owners.
 *
 *         THE FALL RAIL HOLDS EXCEPT IN TWO CASES: the pot running short, and a draw sized
 *         under minDraw, which pays nothing. The payout ordering exists to keep that rule;
 *         see payout().
 *
 *         THE POT'S SIZE IS LEFT TO THE HOST. With pace set below 100% of breakeven, on a
 *         flat book breakeven drifts upward: a bigger pot earns more yield, more yield
 *         raises breakeven, and the pot keeps compounding. Taking the top off is a host
 *         decision, made from outside, through `spare()` or the host's own rule.
 *
 * @author DYBL Foundation
 */
library Breath {

    uint256 internal constant BPS = 10_000;

    error BadAlpha();
    error BadPace();
    error BadTrend();
    error BadShare();
    error BadRails();
    error BadCover();
    error BadRho();

    /// @notice Deploy-time dials. Every one is a rail breath works inside, never a schedule.
    struct Config {
        uint16  slowAlphaBps;   // slow income average, the trajectory
        uint16  fastDownBps;    // fast average when income falls: quick, by temperament
        uint16  fastUpBps;      // fast average when income rises: slower than falling
        uint16  floorBps;       // prize floor, share of the fast average
        uint16  creepBps;       // creep step per draw, share of the slow average
        uint16  paceMinBps;     // pace when the trend is falling
        uint16  paceMaxBps;     // pace when the trend is rising
        uint16  trendLoBps;     // trend at or below this pins pace to paceMin
        uint16  trendHiBps;     // trend at or above this pins pace to paceMax
        uint16  riseBps;        // most the payout may climb in one draw
        uint16  fallBps;        // most it may drop in one draw, subject to release
        uint16  coverTarget;    // cover (pot / this draw's prize) the reserve is held at.
                                 // Surplus above it is what `spare()` is allowed to offer;
                                 // below it there is nothing spare and the answer is zero.
        uint16  spareShareBps;  // share of the surplus a single call may take. Under BPS so
                                 // one call can never take the whole surplus, which is what
                                 // makes repeated asks descend on their own rather than
                                 // needing a hardcoded ladder. NOTE: whichever of this and
                                 // the caller's own ceiling is smaller does the real sizing.
                                 // For example, at 25% with coverTarget 40 and a caller
                                 // ceiling of 1.5% of the pot, this binds only below about
                                 // 43x cover; above that the ceiling is the rule and this
                                 // dial is inert. `spareParts` reports both, so it is visible
                                 // which one bound.
        uint128 minDraw;        // below this a draw is not worth its randomness fee
    }

    struct State {
        uint256 slow;
        uint256 fast;
        uint256 lastPaid;
        bool    started;
    }

    /// @notice What bound the payout. Reported so a caller can see the machine's reasoning.
    enum Bind { FLOOR, CREEP, BREAKEVEN, RISE_RAIL, FALL_RAIL, POT, DUST }

    /// @notice Rejects a configuration that could misbehave in a way no later check catches.
    /// @dev    Bounds are the deploy-time discipline: a dangerous configuration must be
    ///         impossible, not merely discouraged. A mid-life lock is a far worse failure
    ///         than a reverting constructor.
    function validate(Config memory c) internal pure {
        if (c.slowAlphaBps == 0 || c.slowAlphaBps >= c.fastDownBps)   revert BadAlpha();
        if (c.fastUpBps == 0 || c.fastUpBps > c.fastDownBps)          revert BadAlpha();
        // The fast average must be faster than the slow one in BOTH directions. Without
        // this a legal configuration makes it slower on the way up, which inverts the trend
        // and has the game reading a recovery as a decline.
        if (c.slowAlphaBps >= c.fastUpBps)                            revert BadAlpha();
        if (c.fastDownBps > BPS)                                      revert BadAlpha();
        if (c.paceMinBps == 0 || c.paceMinBps > c.paceMaxBps)         revert BadPace();
        if (c.paceMaxBps > BPS)                                       revert BadPace();
        // AND THE BAND MUST STRADDLE PARITY. Ordering alone was not enough: a pair both above
        // parity (or both below) is legal by that test and puts every real trend outside the
        // band, so pace pins to one end forever and the game reads recoveries as decline, or
        // declines as recoveries. A dangerous configuration must be impossible at deploy, and
        // this one deployed cleanly.
        if (c.trendLoBps >= c.trendHiBps)                             revert BadTrend();
        if (c.trendLoBps >= BPS || c.trendHiBps <= BPS)               revert BadTrend();
        if (c.floorBps == 0 || c.floorBps > BPS)                      revert BadShare();
        if (c.creepBps > 1_000)                                       revert BadShare();
        if (c.riseBps <= BPS || c.fallBps >= BPS || c.fallBps == 0)   revert BadRails();
        if (c.coverTarget == 0)                                       revert BadCover();
        // A call that could take the entire surplus would empty the band in one go and
        // leave nothing to descend from, which is the whole reason the ladder is emergent.
        if (c.spareShareBps == 0 || c.spareShareBps >= BPS)           revert BadCover();
        // The opening prize must sit well under breakeven. At a high floor the prize starts
        // near what income supports, so an early collapse leaves the fall rail holding a
        // payout a young pot cannot fund and the prize takes a hard step. Measured: at 55%
        // a 99% wipeout in week two cost 73%, at 25% it costs 46% and is gone by week six.
        // Bounded here rather than left to a deploy-time choice nobody rechecks.
        if (c.floorBps > 4_000)                                       revert BadShare();
        // ZERO IS LEGAL, AND IT MEANS OFF. The guard protects the operator's running costs and
        // the dignity of the prize, not solvency, in a host where randomness is paid from a
        // subscription and gas by whoever triggers the draw. Against that it can trap a field
        // that is able to pay but unable to clear the guard: it cannot run a draw, and it
        // cannot lift its own income to escape, because a player already holding a ticket for
        // the pending draw cannot buy another. A host that would rather pay for every draw
        // sets zero and takes on the zero-amount case itself; a host that wants the guard sets
        // a figure.
        // AND IT MUST NOT BE SO HIGH THAT ORDINARY GAMES CANNOT PAY. The dial decides how wide
        // that trapped band is, so it takes a ceiling rather than a deployer's judgement: ten
        // thousand whole tokens at six decimals, which is what 10_000e6 is. The literal assumes
        // six decimals. On an 18-decimal asset the same ceiling is a hundred-millionth of a
        // token, so any guard a host could set is dust and the guard is effectively off.
        if (c.minDraw > 10_000e6)                                     revert BadShare();

    }

    /// @notice Folds this draw's net income into both averages.
    /// @dev    Call ONCE per draw, from one site. Twice double-weights the draw.
    function observe(State storage s, Config memory c, uint256 net) internal {
        if (!s.started) {
            s.slow = net;
            s.fast = net;
            s.started = true;
            return;
        }
        s.slow = _ema(s.slow, net, c.slowAlphaBps);
        s.fast = _ema(s.fast, net, net >= s.fast ? c.fastUpBps : c.fastDownBps);
    }

    /// @notice What this draw may pay, and which rule bound it. A game that has not started,
    ///         or an empty pot, returns zero with bind DUST rather than POT.
    /// @param  pot       Prize money on hand.
    /// @param  yieldWk   Yield credited to the pot this draw.
    /// @param  rhoBps    Share of a prize that comes back to the pot. Measure it from the
    ///                   host's own flows rather than assuming it. Must be under BPS or
    ///                   breakeven is unbounded.
    /// @dev    ORDER IS LOAD-BEARING and covered by a mutation-verified test. Creep is
    ///         capped by breakeven at every step, not merely collided with later; the rails
    ///         apply after that cap; the pot cap applies last. Apart from the dust guard, the
    ///         pot cap is the only step that may cut harder than the fall rail.
    function payout(
        State storage s,
        Config memory c,
        uint256 pot,
        uint256 yieldWk,
        uint256 rhoBps
    ) internal view returns (uint256 amount, Bind bind) {
        if (rhoBps >= BPS) revert BadRho();
        if (!s.started || pot == 0) return (0, Bind.DUST);

        uint256 slow = s.slow;
        uint256 fast = s.fast;

        // BREAKEVEN. Pay this and, when this draw's income matches the fast average, the
        // pot neither grows nor shrinks.
        uint256 breakeven = ((fast + yieldWk) * BPS) / (BPS - rhoBps);

        // PACE, continuous in trend. Stepping it at mode boundaries would put a jump in the
        // one place the design exists to remove jumps from.
        uint256 trend = slow == 0 ? BPS : (fast * BPS) / slow;
        uint256 pace;
        if (trend <= c.trendLoBps) {
            pace = c.paceMinBps;
        } else if (trend >= c.trendHiBps) {
            pace = c.paceMaxBps;
        } else {
            pace = c.paceMinBps
                 + ((c.paceMaxBps - c.paceMinBps) * (trend - c.trendLoBps))
                   / (c.trendHiBps - c.trendLoBps);
        }
        uint256 target = (breakeven * pace) / BPS;

        // INTENT: creep from the last payout, never below the income floor. "Never" is the
        // INTENT of this line, not a property of the returned amount: the breakeven cap and
        // the rise rail both size below the floor when they bind, which is the ordering doing
        // its job. The floor is a
        // share of income AND this draw's yield, so a growing reserve can lift a game back
        // over the dust threshold on its own.
        uint256 floorAmt = ((fast + yieldWk) * c.floorBps) / BPS;
        uint256 want = s.lastPaid + ((slow * c.creepBps) / BPS);
        bind = Bind.CREEP;
        if (want < floorAmt) { want = floorAmt; bind = Bind.FLOOR; }

        // CAP BY BREAKEVEN, every step. Creep that only checks the pot sails past breakeven
        // and drains the mountain; the collision is not enough, the cap has to be here.
        amount = want;
        if (amount > target) { amount = target; bind = Bind.BREAKEVEN; }

        // RAILS. GLIDE BEATS JUMP. Apart from the dust guard, the pot cap below is the only
        // step in this library that may cut a payout harder than the fall rail.
        if (s.lastPaid != 0) {
            uint256 up = (s.lastPaid * c.riseBps) / BPS;
            uint256 dn = (s.lastPaid * c.fallBps) / BPS;
            if (amount > up) { amount = up; bind = Bind.RISE_RAIL; }
            if (amount < dn) { amount = dn; bind = Bind.FALL_RAIL; }
        }

        if (amount > pot) { amount = pot; bind = Bind.POT; }
        if (amount < c.minDraw) return (0, Bind.DUST);
    }

    /// @notice What a host channel may take on top of this draw, without touching the
    ///         weekly prize or the reserve the game runs on.
    /// @param  weeklyPrize This draw's sized payout, from `payout` above.
    /// @param  maxShareBps A ceiling the CALLER imposes, so a channel can be more cautious
    ///                     than the library. Pass BPS for no extra ceiling.
    /// @dev    THE LADDER IS EMERGENT, NOT WRITTEN DOWN. Each call may take only a share of
    ///         the surplus above the cover target, so a run of calls descends on its own as
    ///         the surplus shrinks, and climbs again when the pot rebuilds. Nothing here
    ///         knows about quarters, decline, or how many times it has been asked: the host
    ///         owns the rhythm, this owns the amount, and the answer is zero whenever the
    ///         reserve is not genuinely above target.
    ///
    ///         SELF-LIMITING BY CONSTRUCTION. Because the figure is a fraction of the
    ///         surplus ABOVE the target, it cannot pull the pot below the target however
    ///         often it is called. That is why no separate floor is needed underneath it.
    function spare(
        Config memory c,
        uint256 pot,
        uint256 weeklyPrize,
        uint256 maxShareBps
    ) internal pure returns (uint256 amount) {
        (amount, , ) = spareParts(c, pot, weeklyPrize, maxShareBps);
    }

    /// @notice `spare`, with both candidate figures exposed so a caller or a test can see
    ///         WHICH limit did the sizing rather than inferring it.
    /// @dev    The two limits are easy to misread: the dial that looks like the sizing rule
    ///         (`spareShareBps`) can be inert while the caller's ceiling does the work (see
    ///         the example on Config). A reader looking only at the config would draw the
    ///         wrong conclusion.
    function spareParts(
        Config memory c,
        uint256 pot,
        uint256 weeklyPrize,
        uint256 maxShareBps
    ) internal pure returns (uint256 amount, uint256 shareOffer, uint256 ceiling) {
        if (weeklyPrize == 0 || maxShareBps == 0) return (0, 0, 0);
        uint256 reserve = uint256(c.coverTarget) * weeklyPrize;
        if (pot <= reserve) return (0, 0, 0);
        shareOffer = ((pot - reserve) * c.spareShareBps) / BPS;
        ceiling    = (pot * maxShareBps) / BPS;
        amount     = shareOffer < ceiling ? shareOffer : ceiling;
    }

    /// @notice Records what was paid, for the next draw to step from.
    /// @dev    A boost or an emergency release is deliberately NOT committed here. If it
    ///         were, the fall rail would treat the boosted week as the new normal and
    ///         refuse to let the prize back down, so a single boost would drag every
    ///         following week upward. Only the weekly prize is breathing state.
    function commit(State storage s, uint256 paid) internal {
        s.lastPaid = paid;
    }

    function _ema(uint256 prev, uint256 next, uint256 a) private pure returns (uint256) {
        if (next >= prev) return prev + (((next - prev) * a) / BPS);
        return prev - (((prev - next) * a) / BPS);
    }
}
