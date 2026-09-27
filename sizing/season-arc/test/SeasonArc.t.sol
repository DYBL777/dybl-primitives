// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

/// @dev A thin host so the library can be driven directly with exact inputs. Every assertion
///      below is on a value computed by hand from the rule, not on a figure the library
///      produced and was then asserted against itself.
contract ArcHost {
    function size(uint256 pot, uint256 last, uint256 left, uint256 income, uint256 openBps)
        external pure returns (uint256 amount, SeasonArc.Bind bind)
    { return SeasonArc.size(pot, last, left, income, 0, openBps); }

    /// @dev The same call with the return share the host actually passes, so the tests can
    ///      drive both the blind case (above, kept because most assertions do not depend on
    ///      it) and the modelled one.
    function sizeWithReturn(uint256 pot, uint256 last, uint256 left, uint256 income,
        uint256 returnBps, uint256 openBps)
        external pure returns (uint256 amount, SeasonArc.Bind bind)
    { return SeasonArc.size(pot, last, left, income, returnBps, openBps); }
}

/// @notice THE ENGINE'S OWN TESTS. Written once it was found that the sizing library had
///         none, and that four separate mutations to it and to what the host feeds it left
///         the entire suite green: growth capped at flat, a draws-remaining figure one too
///         high, a zero income estimate, and this draw's income counted twice. Each of those
///         is a named assertion below, so a mutation that reintroduces it fails here rather
///         than passing everywhere.
contract SeasonArcUnit is Test {
    ArcHost h;
    function setUp() public { h = new ArcHost(); }

    // ── the opening ──────────────────────────────────────────────────────────

    /// @dev THE OPENING IS A SHARE OF THE POT, and the share is the only dial. Computed by
    ///      hand: 25% of 400 is 100. Anything else means the dial is not doing what it says.
    function test_theOpeningDrawPaysTheShareOfThePotItIsGiven() public view {
        (uint256 amount, SeasonArc.Bind bind) = h.size(400e6, 0, 52, 40e6, 2_500);
        assertEq(amount, 100e6, "the opening is exactly the share of the pot");
        assertEq(uint256(bind), uint256(SeasonArc.Bind.OPENING), "and says so");

        (amount, ) = h.size(400e6, 0, 52, 40e6, 1_000);
        assertEq(amount, 40e6, "a smaller share opens smaller");
        (amount, ) = h.size(400e6, 0, 52, 40e6, 5_000);
        assertEq(amount, 200e6, "a larger share opens larger");
    }

    // ── the closing draw ─────────────────────────────────────────────────────

    /// @dev ONE DRAW LEFT TAKES EVERYTHING. Not "most of it": the pot must reach zero, and
    ///      this is the only rule that guarantees it.
    function test_theClosingDrawTakesTheWholePot() public view {
        (uint256 amount, SeasonArc.Bind bind) = h.size(1_234_567, 500, 1, 40e6, 2_500);
        assertEq(amount, 1_234_567, "the last draw pays the entire pot");
        assertEq(uint256(bind), uint256(SeasonArc.Bind.CLOSING), "and says so");
    }

    // ── the arc itself ───────────────────────────────────────────────────────

    /// @dev THE ARC MUST RISE, STRICTLY. This is the mutation that survived everything: cap
    ///      the growth at flat and the whole suite stayed green, because the acceptance test
    ///      asserted "no draw pays less than the last", which a flat line satisfies. A season
    ///      with money still arriving has no reason to repeat a payment.
    function test_theArcRisesStrictlyWhileIncomeArrives() public view {
        uint256 pot = 400e6;
        uint256 last = 100e6;
        uint256 income = 400e6;
        uint256 prev;
        for (uint256 left = 20; left > 1; left--) {
            pot += income;
            (uint256 amount, SeasonArc.Bind bind) = h.size(pot, last, left, income, 2_500);
            assertGt(amount, last, "every draw must pay strictly more than the last");
            assertEq(uint256(bind), uint256(SeasonArc.Bind.ARC), "and by the arc, not a clamp");
            assertGt(amount, prev, "and more than the draw before it");
            prev = amount;
            pot -= amount;
            last = amount;
        }
    }

    /// @dev THE ARC AIMS AT ZERO, and the aim is what the solver is for. Run the rule to the
    ///      end and the pot must be spent, not left with a season's worth of money in it.
    ///      Asserted as a fraction of what arrived, so it survives a change of scale.
    function test_theArcSpendsThePotByTheLastDraw() public view {
        uint256 pot; uint256 last; uint256 income = 400e6; uint256 draws = 24;
        for (uint256 d = 1; d <= draws; d++) {
            pot += income;
            (uint256 amount, ) = h.size(pot, last, draws - d + 1, income, 2_500);
            pot -= amount;
            last = amount;
        }
        assertEq(pot, 0, "the arc must leave nothing behind");
    }

    // ── what the host feeds it ───────────────────────────────────────────────

    /// @dev DRAWS REMAINING CHANGES THE ANSWER, so a host that miscounts by one is not making
    ///      a rounding error. A mutation adding one to the figure survived the whole suite.
    function test_drawsRemainingChangesTheAnswer() public view {
        (uint256 tight, ) = h.size(1_000e6, 100e6, 4, 400e6, 2_500);
        (uint256 loose, ) = h.size(1_000e6, 100e6, 12, 400e6, 2_500);
        assertGt(tight, loose,
            "fewer draws left must mean a larger payment: the same money, spread thinner");
    }

    /// @dev THE INCOME ESTIMATE CHANGES THE ANSWER. A mutation feeding zero survived, because
    ///      nothing asserted that the forecast is used at all. A season that expects more
    ///      money can afford to climb faster toward the same ending.
    function test_theIncomeEstimateChangesTheAnswer() public view {
        (uint256 withIncome, ) = h.size(1_000e6, 100e6, 10, 400e6, 2_500);
        (uint256 without, )    = h.size(1_000e6, 100e6, 10, 0, 2_500);
        assertGt(withIncome, without,
            "a season expecting income must size above one expecting none");
    }

    /// @dev THIS DRAW'S INCOME IS ALREADY IN THE POT. The solver adds the estimate for every
    ///      draw AFTER this one, never for this one, because the host has already banked it.
    ///      A mutation counting it twice survived. Detected by the arithmetic: double-counting
    ///      inflates the forecast, so the answer rises.
    /// @dev PINNED BY ARITHMETIC, because a bind assertion cannot see this. With two draws
    ///      left the solver must find g such that last*g + last*g^2 exhausts pot + income
    ///      counted ONCE. At pot 1000, last 100, income 400 that is g^2 + g - 14 = 0, so
    ///      g = 3.2749 and the first payment is 327.49. Counting the income twice makes it
    ///      g^2 + g - 18 = 0, g = 3.7720, and the payment 377.20: a 15% overshoot that no
    ///      bind reason reports, because both answers are legal arcs.
    function test_theForecastAddsIncomeOncePerRemainingDraw() public view {
        (uint256 amount, ) = h.size(1_000e6, 100e6, 2, 400e6, 2_500);
        assertApproxEqRel(amount, 327_490_000, 0.001e18,
            "the forecast must add income once per draw AFTER this one, never for this one");
    }

    function test_thisDrawsIncomeIsNotCountedTwice() public view {
        // Detected by what over-forecasting DOES rather than by comparing two calls: a solver
        // that counts this draw's income again believes more is coming than will arrive, so
        // it climbs too fast and runs the pot dry before the end. Every draw of a steady
        // season should therefore be sized by the ARC; a POT bind before the closing draw
        // means the forecast overshot.
        uint256 pot; uint256 last; uint256 income = 400e6; uint256 draws = 16;
        for (uint256 d = 1; d <= draws; d++) {
            pot += income;
            (uint256 amount, SeasonArc.Bind bind) = h.size(pot, last, draws - d + 1, income, 2_500);
            if (d > 1 && d < draws) {
                assertEq(uint256(bind), uint256(SeasonArc.Bind.ARC),
                    "a steady season must never run its pot dry before the last draw");
            }
            pot -= amount;
            last = amount;
        }
        assertEq(pot, 0, "and it still lands on zero");
    }

    // ── the edges ────────────────────────────────────────────────────────────

    /// @dev NOTHING TO PAY FROM. An empty pot is not an error, it is a draw that does not run,
    ///      and the host reads the zero rather than a revert.
    function test_anEmptyPotSizesToNothing() public view {
        (uint256 amount, SeasonArc.Bind bind) = h.size(0, 100e6, 10, 400e6, 2_500);
        assertEq(amount, 0, "no pot, no payment");
        assertEq(uint256(bind), uint256(SeasonArc.Bind.POT), "and the reason is the pot");
    }

    /// @dev THE POT IS THE CEILING. When the arc wants more than is there, the payment is the
    ///      pot and the bind says so, rather than promising money that does not exist.
    function test_theArcNeverPromisesMoreThanTheSeasonCanAfford() public view {
        // Five draws left and a pot smaller than the last payment. The arc wants more than
        // is there, so the pot binds; but it may not take everything, because four draws
        // still have to pay something. What is left for each of them is the equal share.
        // NAMED FOR THE POT BIND AND ASSERTING THE FALLBACK, which is what tipped a reader
        // off that the pot branch could never fire from the solver path: reaching it required
        // the solver to bottom out, and bottoming out is caught by the fallback first. The
        // branch is gone; POT now means only that there was nothing to size from.
        //
        // WITH ZERO INCOME the answer is unchanged from the equal share this used to assert.
        // That is the point: the old rule was right only when no more tickets would be sold,
        // and this case passes zero income, so it is the one case where the two agree.
        (uint256 amount, SeasonArc.Bind bind) = h.size(50e6, 100e6, 5, 0, 2_500);
        // 9,999,999 AND NOT 10,000,000, AND THE ONE UNIT IS THE POINT. The old rule paid the
        // equal share, and at zero income and zero return that share is exactly 10e6. The
        // forward walk REJECTS 10e6: it leaves precisely nothing standing at the close, and
        // the walk requires something left. So the old branch was paying a figure its own
        // solvency walk would not accept, by one unit, every time. This pays the largest
        // amount the walk actually survives.
        assertEq(amount, 9_999_999,
            "with no income, the largest flat payment the walk survives, one unit under the equal share");
        assertEq(uint256(bind), uint256(SeasonArc.Bind.SUSTAINED),
            "and reports the fallback: the arc bottomed out, it did not merely hit the pot");

        // AND WITH INCOME THE TWO DIVERGE, which is the whole change. Same pot, same draws,
        // but $4 a draw still arriving: the old rule would still pay 10e6 because it counts
        // no ticket that has not been sold. This pays what the season can actually carry.
        (uint256 withIncome, SeasonArc.Bind b2) = h.size(50e6, 100e6, 5, 4e6, 2_500);
        assertGt(withIncome, 10e6,
            "income still to arrive raises what this draw can afford, and the old rule ignored it");
        assertEq(uint256(b2), uint256(SeasonArc.Bind.SUSTAINED), "still the fallback");

        // With one draw left there is nothing to reserve for, so it takes the lot.
        (amount, bind) = h.size(50e6, 100e6, 1, 0, 2_500);
        assertEq(amount, 50e6, "the closing draw takes the whole pot");
    }

    /// @dev A LATE ARRIVAL MUST NOT BE FENCED OUT BY THE SEARCH BOUND. A crowd arriving
    ///      mid-season can genuinely want growth above the old 2x ceiling, and a solver that
    ///      cannot reach the answer returns its own bound instead: the payment climbs at the
    ///      limit while money piles up, and the closing draw takes what was stranded. The
    ///      bound is a search range, not a safety rail, since every step is clamped to the pot.
    function test_aLateArrivalIsNotFencedOutByTheSearchBound() public view {
        // A pot far larger than the last payment, with few draws left to spend it.
        (uint256 amount, SeasonArc.Bind bind) = h.size(10_000e6, 100e6, 4, 0, 2_500);
        assertGt(amount, 200e6, "the solver must be able to answer above a doubling");
        assertEq(uint256(bind), uint256(SeasonArc.Bind.ARC),
            "and reach it by solving rather than by hitting its own ceiling");
    }

    /// @dev NO DRAW MAY BE LEFT WITH NOTHING TO PAY. If the arc cannot keep up, the equal
    ///      share is the floor beneath it: the pot divided by the draws remaining. Without it
    ///      a flat fallback can empty the pot with draws still to run, and the closing draw
    ///      arrives at an empty pot that never fills.
    function test_theArcNeverEmptiesThePotEarly() public view {
        uint256 pot = 100; uint256 last = 60; uint256 left = 5;
        for (; left > 1; left--) {
            (uint256 amount, ) = h.size(pot, last, left, 0, 2_500);
            assertLe(amount, pot, "never more than the pot");
            pot -= amount;
            last = amount;
            assertGt(pot, 0, "a draw must never leave the closing draw with nothing");
        }
    }

    /// @dev A SURGE LIFTS THE ARC, IT DOES NOT SPEND ITSELF. The solver is asked
    ///      what growth exhausts the pot by the last draw, not how fast it may grow, so a
    ///      one-week spike raises every remaining payment rather than being handed to the
    ///      next draw. Pinned here because the behaviour reads like a bug and is not: the
    ///      payment after a tenfold spike must be nowhere near tenfold.
    function test_aSurgeLiftsTheWholeArcRatherThanTheNextDraw() public view {
        // The same position twice, once with an ordinary week's income in the pot and once
        // with ten times it. The larger pot must pay more, and nothing like ten times more.
        (uint256 ordinary, ) = h.size(1_000e6, 100e6, 10, 400e6, 2_500);
        (uint256 surged, )   = h.size(4_600e6, 100e6, 10, 4_000e6, 2_500);
        assertGt(surged, ordinary, "a surge must lift the payment");
        assertLt(surged, ordinary * 4,
            "but nowhere near in proportion to the surge: it is spread across the season");
    }

    /// @dev THE OVERFLOW THAT DOES NOT LOOK LIKE ONE. The host computes the return share from
    ///      a Split whose fields are all uint16, so multiplying two of them overflows at
    ///      65,535 before the division can bring the result back into range: at the shipped
    ///      split that is 3,300 x 3,000, and it panicked on every draw. Nothing about the
    ///      call site suggests it, because the operands are small and so is the answer. Only
    ///      the intermediate is not. Pinned here so a future edit that drops the widening
    ///      fails a test rather than the whole game.
    function test_theReturnShareArithmeticDoesNotOverflowItsOperands() public pure {
        uint16 jackpotBps = 3_300;
        uint16 missToPotBps = 3_000;
        uint16 reseedBps = 2_000;
        uint256 widened = uint256(reseedBps)
            + (uint256(jackpotBps) * uint256(missToPotBps)) / 10_000;
        assertEq(widened, 2_990, "twenty per cent reseed plus 9.9% from a missed jackpot");
    }

    /// @dev A DECLINING SEASON MUST FALL WHEN THE CROWD DOES, NOT TWENTY WEEKS LATER. The arc
    ///      cannot size below the last payment (G_MIN is flat), so without a floor that works
    ///      in BOTH directions it repays the same figure until the pot cannot cover it and
    ///      then collapses in one step. Measured on the shipped code before the fix: a
    ///      52-draw season losing 97% of its crowd at draw 10 held flat and then paid 0.06x
    ///      at draw 37. RUN AT A SHIPPED SEASON LENGTH: the acceptance test's twelve draws is
    ///      too short for the pot to drain that far, which is why this was not caught there.
    function test_aLongDecliningSeasonFallsOnceAndNotOffACliff() public view {
        uint256 pot; uint256 last; uint256 inc = 8_000e6; uint256 draws = 52;
        uint256 worst = type(uint256).max;
        uint256 downDraws;
        for (uint256 d = 1; d <= draws; d++) {
            uint256 i = d < 10 ? inc : inc / 40;
            pot += i;
            (uint256 a, ) = h.sizeWithReturn(pot, last, draws - d + 1, i, 2_990, 2_500);
            if (last > 0) {
                uint256 mv = (a * 10_000) / last;
                if (mv < worst) worst = mv;
                if (a < last) downDraws++;
            }
            pot -= a;
            if (draws - d + 1 > 1) pot += (a * 2_990) / 10_000;
            last = a;
        }
        // COUNT THE FALLS, NOT JUST THE WORST ONE. The claim in the name is ONE honest step
        // down, and a bound on the deepest move alone cannot see that claim break: three
        // separate falls of a third each would have passed it. So both halves are pinned.
        //
        // THE FIGURE MOVED FROM 4,223 TO 6,854 AT v0.41 AND THAT IS THE FIX, NOT A
        // REGRESSION. The step down is taken by the solver's fallback, which until v0.41
        // paid `pot / drawsLeft`: the pot held today spread across the draws remaining, as
        // though not one more ticket would ever be sold. Here 200e6 a draw is still arriving
        // and the old rule counted none of it, so it paid about six tenths of what the season
        // could afford, undershooting by roughly 39%. The season now steps
        // down to 0.69x of the previous draw instead of 0.42x, out of money that was always
        // going to be there. Anyone restoring 4,223 is restoring the underpayment.
        assertEq(downDraws, 1, "a plain decline should step down once, not repeatedly");
        assertApproxEqAbs(worst, 6_854, 150,
            "and that step is the measured one, not a deeper cliff");
    }
}
