// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1
// Change Date: 1 February 2030. On the Change Date, available under MIT.
pragma solidity 0.8.24;

/**
 * @title  SeasonArc
 * @notice Prize sizing for a game that knows when it ends, by a SOLVED GROWTH ARC.
 *
 * @dev    NAMED FOR THE RULE, NOT THE FAMILY. There is more than one honest way to size a
 *         season, and a sibling host in this suite reaches the same goal by a different rule:
 *         an EQUAL-SHARE GLIDE, tank divided by draws remaining, which lands on zero
 *         arithmetically (at one draw left it pays everything, it cannot do otherwise) and
 *         rises as a side effect, because the tank grows while the divisor shrinks. That
 *         belongs under its own name, SeedGlide, and this library must not take the general
 *         one from it.
 *
 *         WHY A TICKET-FUNDED HOST CANNOT USE THAT RULE. The glide works when the opening
 *         draw is allowed to be tiny, which is true of a game paying out yield on parked
 *         capital: nobody expects much in week one. Lettery TF, the host this library was
 *         written for, pays out TICKET money, and its smallest tier must clear the ticket
 *         price from the first draw. Modelled at a hundred
 *         thousand tickets a week, an equal-share glide opened at a fraction of a cent per
 *         match-3 winner and did not clear a five dollar ticket for the first several draws.
 *         THAT MODEL IS NOT IN THIS REPOSITORY: treat it as the reason the rule was chosen,
 *         not as evidence you can rerun. Demand a real opening and
 *         you have spent a large share of the pot early, at which point equal shares
 *         afterwards FALL rather than rise. So this rule grows from the last payment and
 *         solves for the ending, where the glide needs no solver at all. The difference
 *         traces back to ticket buys versus parked yield, and nowhere else.
 *
 * @dev    ONE QUESTION, AND IT IS NOT THE PERPETUAL ONE. Breath asks "what can this draw
 *         afford, sustained forever", and has to answer from income averages, a breakeven
 *         anchor and rails, because a perpetual game has no end to aim at. This library asks
 *         a different question: "what should this draw pay so that payments RISE across the
 *         season and the pot is spent down to the last draw". A season has an end, so aiming
 *         at it is honest rather than a guess, and the machinery that exists to avoid guessing
 *         is not needed here. The library sizes the last draw at the whole pot it is shown;
 *         whether the host's pot is then empty is the host's business, and in Lettery TF it
 *         is not, because the host withholds from that draw like any other.
 *
 *         THE RULE.
 *
 *           pay(d) = pay(d-1) * g
 *
 *         where g is solved fresh every draw so that continuing at that growth exhausts the
 *         pot over the draws that remain. The first draw is a share of the pot, chosen at
 *         deploy: that is the ONLY dial, and it sets both how large the opening prize is and
 *         how steep the arc that follows.
 *
 *         WHY RE-SOLVE EVERY DRAW rather than fix g at deploy. The pot is fed by ticket
 *         income, which moves. A g fixed on day one against an assumed crowd would either
 *         strand money (crowd larger than assumed) or run the pot dry before the last draw
 *         (crowd smaller). Re-solving means the arc bends to what actually happened instead
 *         of to what was predicted, and the only forecast it makes is that the income just
 *         observed continues, which is the least it can assume and still aim at an ending.
 *
 *         NO RAILS, AND THAT IS AN EVIDENCED DELETION rather than an omission. The perpetual
 *         host caps how far a payment may move from the last one, because its sizing reacts
 *         to income and income can crash. Here the payment is a share of a STOCK: the pot
 *         dominates the weekly inflow within a few draws, so a collapse in ticket sales moves
 *         the numerator slowly while the denominator falls by one every draw regardless.
 *         THE SHAPE ON A COLLAPSE IS ONE STEP, not a gentle decline: at 52 draws with the
 *         crowd dropping 97% at draw 10, and the last payment passed unscaled as the stand-in
 *         does, the payment steps down once in the week the crowd leaves and is carried flat
 *         after it (test/StandIn.t.sol). A host that scales the last payment by field steps
 *         down by the field ratio and climbs from there. A rail would have nothing to catch
 *         on the way UP either, which is the other reason there is none.
 *
 *         WHAT THIS LIBRARY DOES NOT DO. It does not know about tiers, reseed, the jackpot
 *         roll. It answers with an amount; the host splits it and withholds from it, so a
 *         host that withholds on its closing draw ends with that share still held.
 *
 * @dev    ONE DEPLOYED COPY, CALLED BY ITS HOSTS. `size` is external, so a host links to a
 *         deployed SeasonArc rather than carrying the solver in its own bytecode. The library
 *         is pure: it reads and writes no storage, so what it can do in a host's context is
 *         return a number or revert. A host is wired to one address at deploy and cannot be
 *         re-pointed afterwards, so the address it links is part of what that host is.
 */
library SeasonArc {

    /// @notice A payment must return less than it costs, or the search walks the wrong way.
    error BadReturnShare();
    /// @notice The opening share cannot exceed the whole pot. Named for the library rather
    ///         than after any host's own opening-share check, which may be narrower.
    error OpeningShareTooLarge();

    uint256 internal constant BPS = 10_000;

    /// @dev Bounds on the solve. A growth factor is a per-draw multiplier in BPS, so 10_000
    ///      is flat. The upper bound is generous rather than tuned: a season short enough or
    ///      an income stream large enough can genuinely want a steep arc, and the solver is
    ///      bounded by the pot at every step anyway.
    uint256 internal constant G_MIN = 10_000;
    /// @dev THE TOP OF THE SEARCH, NOT A SPEED LIMIT. Do not lower it to read as a safety
    ///      rail: every step of the forward walk is already clamped to the pot, so a large
    ///      candidate is rejected by the same test that rejects a small one. A low ceiling
    ///      only fences the solver out of answers it needs. A crowd arriving mid-season can
    ///      want growth above a doubling, and on isolated calls a ceiling of 20_000 (a doubling)
    ///      can return its own bound rather than the solved answer.
    uint256 internal constant G_MAX = 1_000_000;
    /// @dev Bisection steps. The search spans just under a million basis points, so it closes
    ///      to one in about twenty and the loop breaks as soon as it does; 48 is headroom for
    ///      a wider range rather than a tuned figure, and costs nothing at the shipped one.
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
     *         leaving: the reseed, plus the part of a missed jackpot that goes home. Passing
     *         zero here tells the solver every prize leaves in full, which under-forecasts
     *         the pot by that share on every remaining draw. That error does not compound
     *         into insolvency (the closing draw takes whatever is there) but it deforms the
     *         arc: the money the solver did not know was coming back accumulates and
     *         discharges in one step at the end.
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
        // THE SOLVE RESTS ON THESE, so a host that gets them wrong should stop rather than
        // receive a confident wrong answer. Bisection needs the leftover to fall as g rises,
        // which holds while a payment returns less than it costs; at returnBps >= BPS a
        // steeper arc would leave MORE behind and the search would walk the wrong way. An
        // opening share above the whole pot is the same class of mistake. Both are free to
        // check and neither can be caught downstream: the numbers just come out wrong.
        if (returnBps >= BPS) revert BadReturnShare();
        if (openingBps > BPS) revert OpeningShareTooLarge();
        if (drawsLeft == 0) return (0, Bind.POT);

        // THE CLOSING DRAW TAKES EVERYTHING, AND IT IS ANSWERED BEFORE THE EMPTY-POT CASE.
        // With one draw left there is no future to spread anything across; a host that
        // withholds on this draw keeps that share, as the header says. The order matters:
        // an empty pot tested first returned POT with a zero amount on the closing draw, which
        // reads as "no draw to size" when the truth is "the closing draw, and there is nothing
        // in the pot". A host that refuses a zero-sized draw then cannot end its season at
        // all, and anything it was holding outside the pot for that draw goes nowhere. The
        // amount is the same either way; the BIND is what a caller acts on.
        if (drawsLeft == 1) return (pot, Bind.CLOSING);

        if (pot == 0) return (0, Bind.POT);

        // THE OPENING. There is no previous payment to grow from, so the first draw is a
        // share of what is there. This is the dial that decides everything downstream: a
        // larger opening means a larger first prize and a shallower arc behind it.
        if (lastPaid == 0) {
            // No clamp against the pot: openingBps is checked at or under BPS on the way in,
            // so a share of the pot cannot exceed it. A guard for a state that cannot occur is
            // removed rather than kept, which is the rule this library and its host both
            // follow, and the check above is what makes it true here.
            return ((pot * openingBps) / BPS, Bind.OPENING);
        }

        uint256 g = _solve(pot, lastPaid, drawsLeft, incomeEstimate, returnBps);
        amount = (lastPaid * g) / BPS;

        // THE FALLBACK IS THE FLOOR BENEATH THE ARC, AND ONLY WHEN THE ARC HAS FAILED.
        // When even flat growth would run the pot dry the solver bottoms out at G_MIN, and
        // the arc alone would then pay `lastPaid` until the pot could not cover it, leaving
        // later draws with nothing and the closing draw arriving at an empty pot. A flat
        // payment the whole season can carry cannot do that.
        //
        // BUT THE SOLVER'S FLOOR IS TWO CASES, AND ONLY ONE OF THEM IS A FAILED ARC. The search
        // never tests G_MIN itself: it returns its lower bound when every steeper factor it
        // tried ran dry, which is also what happens when flat growth still fits and nothing
        // steeper does. So the walk is asked once more, at flat. If flat leaves anything the
        // arc has not failed, it has flattened, and this draw pays what the last one did; the
        // closing draw takes what flat leaves. Only when flat runs dry does the fallback pay.
        //
        // WHAT IT PAYS: the largest flat payment the pot AND its future income can sustain to
        // the close. NOT `pot / drawsLeft`, which spreads today's pot across the draws
        // remaining as though no further ticket will be sold. On a pot of $28,744 with eight
        // draws left and $4,000 a draw still arriving, the equal share pays $3,593 where
        // $9,606.23 is carryable (at a 29.9% return share).
        //
        // GATED ON THE ARC HAVING FAILED, NOT ON THE ARC SIZING BELOW AN EQUAL SHARE, and the
        // distinction is the whole mechanism. A healthy arc deliberately pays LESS than an
        // equal share early, because that is what makes the closing draw large. A floor
        // applied unconditionally flattens every season and the arc stops existing. Growth is
        // untouched: a solver that finds any g above flat never reaches this line.
        //
        // THE SOLVER'S ARC DOES NOT CHOOSE A DECLINE; THE FALLBACK CAN STEP DOWN. G_MIN is
        // flat, so the search never picks a factor below one. This fallback can step down
        // once, when the pot cannot carry the last payment flat. A host may also hand in the
        // last payment scaled by the change in field (Lettery TF does), so a shrinking crowd
        // scales the anchor down before this function sees it. With the last payment passed
        // unscaled, as the stand-in does, a 52-draw season whose crowd drops 97% at draw 10
        // steps down once, in the week the crowd leaves, and is carried flat to the end
        // (test/StandIn.t.sol); a host that scales it by field steps down by the field ratio
        // and climbs from there.
        //
        // DO NOT REGATE THIS ON `amount < equalShare`. That gate can only fire when the arc
        // is too SHALLOW, which is never the dangerous case:
        // when the pot is draining, lastPaid is LARGER than the equal share, so the net was
        // structurally unable to catch what it existed for.
        if (g == G_MIN) {
            if (_leftover(pot, lastPaid, drawsLeft, incomeEstimate, returnBps, G_MIN) > 0) {
                return (amount, Bind.ARC);
            }
            return (_maxSustainable(pot, drawsLeft, incomeEstimate, returnBps), Bind.SUSTAINED);
        }

        // NO CAP AGAINST THE POT IS NEEDED HERE. `amount >= pot` would need the solver to
        // have returned its lower bound, because any g above G_MIN was accepted only where
        // the forward walk left something over, and that walk rejects any first payment at
        // or above the pot. And g == G_MIN is answered above: flat only where the same walk
        // left something over, the fallback otherwise.

        // A pot that grew between draws is handled by the re-solve, not by a floor.
        return (amount, Bind.ARC);
    }

    /// @dev Binary search for the growth factor that exhausts the pot over the remaining
    ///      draws. Monotone in g (a steeper arc always leaves less behind), so bisection is
    ///      exact to the bound's precision and cannot get stuck. The forward walk clamps each
    ///      payment to the pot it is drawn from, so an overshooting candidate simply runs the
    ///      pot to zero early and is rejected by the same test.
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
    /// @dev    CLOSED FORM, NOT A SEARCH, and the reason is worth stating because a bisection
    ///         was written first and was worse in two ways it could not fix.
    ///
    ///         This branch pays at G_MIN, so the payment is FLAT at P every draw. That makes
    ///         the forward walk a straight line rather than something needing exploration.
    ///         Each non-final draw removes P and returns P*returnBps/BPS, so the balance
    ///         standing before draw k is
    ///
    ///             p(k) = pot + k*incomeEstimate - k*P*(BPS - returnBps)/BPS
    ///
    ///         and the walk survives draw k exactly when P < p(k). Rearranged, for every k in
    ///         0 .. drawsLeft-1:
    ///
    ///             P  <  BPS * (pot + k*incomeEstimate) / (BPS + k*(BPS - returnBps))
    ///
    ///         The answer is the smallest of those bounds. The right side has the form
    ///         (A + kB)/(C + kD), which is monotone in k, so the smallest sits at one of the
    ///         two ENDS. Two divisions, and no search bound to justify.
    ///
    ///         THAT IS THE FAST PATH AND NOT THE WHOLE COST: the correction loop below is not
    ///         optional. It bisects a band of width drawsLeft + 2, which is where the headline
    ///         case actually lands. Bounded and small, but an iteration count.
    ///
    ///         WHAT THE BISECTION GOT WRONG, recorded so it is not reintroduced. It needed an
    ///         upper bound and the only one available was invented (pot*20 + income*draws),
    ///         which is finite but arbitrary. And 64 iterations stop resolving to the unit at
    ///         large magnitudes: at a pot of 1e30 it undershoots the true answer by roughly
    ///         1e12. This form is exact there.
    ///
    ///         THE CORRECTION LOOP IS NOT OPTIONAL. Integer division floors the returned
    ///         share, so the real walk keeps up to one unit less per draw than the algebra
    ///         assumes and the closed form can sit up to drawsLeft above what the walk
    ///         survives. The loop closes that band and runs ONLY when the first candidate
    ///         misses. Checked against the bisection it replaces on 40,000 random cases:
    ///         zero difference, zero infeasible answers.
    function _maxSustainable(
        uint256 pot,
        uint256 drawsLeft,
        uint256 incomeEstimate,
        uint256 returnBps
    ) private pure returns (uint256) {
        uint256 spend = BPS - returnBps;          // what a payment costs the pot, net of return

        // The two ends of a monotone family. Minus one turns "P < bound" into "P <= this".
        // `BPS * pot` underflows the minus one at pot == 0; unreachable, because size()
        // returns Bind.POT on an empty pot before this is called, and this is private.
        // INPUT CEILING: the numerator below reverts on overflow
        // above roughly 1.15e73. A revert, not a wrong answer, and far outside any figure a
        // six-decimal token can carry, but the edge is unexplored: the fuzz of this function
        // (test/SustainedFallback.t.sol) bounds the pot at 5e14.
        uint256 first = ((BPS * pot) - 1) / BPS;
        uint256 last  = ((BPS * (pot + (drawsLeft - 1) * incomeEstimate)) - 1)
                        / (BPS + (drawsLeft - 1) * spend);
        uint256 cand  = first < last ? first : last;
        if (cand == 0) return 0;

        // Usually exact. The walk is the arbiter, never the algebra.
        if (_leftover(pot, cand, drawsLeft, incomeEstimate, returnBps, G_MIN) > 0) return cand;

        // It missed by at most drawsLeft units of flooring. Bisect that band only. If drift
        // ever exceeded the band, `lo` lands infeasible and the final check below returns 0
        // rather than a number the walk would reject. That is the safe direction.
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
    ///      Income is added for every draw after this one, since this draw's income has
    ///      already landed in `pot` by the time the host asks. Returns 0 the moment a payment
    ///      meets or exceeds the balance standing before it: that g is too steep.
    ///
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
            // EVERY DRAW TAKES ITS SHARE OUT OF THE POT, AND PART OF IT COMES STRAIGHT BACK.
            // Not on the last remaining draw, and that exclusion is a MODELLING CHOICE rather
            // than a description of any host: a host may withhold there too (Lettery TF does,
            // and what it withholds funds the ending's per-ticket claim rather than a next
            // draw). So every solve under-counts the pot by one draw's returned share. The
            // direction is safe: less forecast money means a shallower arc, so this can only
            // leave more behind and never under-fund a payment. It does mean the arc aims
            // slightly below what the game can afford, which tilts money from the weekly
            // prizes toward the ending. Left alone deliberately: correcting it changes what the
            // solver pays for every host, and KNOWN_ISSUES records it.
            // Divide AFTER multiplying, deliberately. A linter flags this shape as a
            // precision risk and here it is the correct order: `pay * returnBps` is exact and
            // dividing first would floor `returnBps / BPS` to zero. Noted so a reviewer does
            // not raise it as a finding.
            if (k + 1 < drawsLeft) p += (pay * returnBps) / BPS;
        }
        return p;
    }
}
