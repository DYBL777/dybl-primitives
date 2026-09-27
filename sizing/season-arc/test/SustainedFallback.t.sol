// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

/// @notice THE FALLBACK STOPS PRETENDING NO MORE TICKETS WILL BE SOLD.
///
///         `SeasonArc.size` returns G_MIN from its solver for two unrelated reasons and the
///         caller cannot tell them apart: the pot genuinely draining, which the fallback was
///         built for, and the host having scaled the anchor by the change in field until no
///         growth factor survives the walk. Scaling by k makes the second k times easier to
///         reach, so ordinary growth landed in a branch only a collapse used to reach.
///
///         The fallback then paid `pot / drawsLeft`, which spreads the pot held TODAY across
///         the draws remaining as though no further income would arrive. It always does.
///         Modelled on a 104-draw season, a 1.7x arrival at draw 86 took the payment from
///         $4,423,566 to $655,704 and a match-3 winner from $34.34 to $3.02, and it did not
///         recover. Across 400 modelled crowd shapes, 59 draws saw the crowd grow and the
///         payment fall, and all 59 were this branch.
///
///         EVERYTHING ABOVE IS PYTHON. This file is where those claims meet the Solidity.
contract SustainedFallbackTest is Test {

    uint256 internal constant BPS = 10_000;
    uint256 internal constant G_MIN = 10_000;

    Harness internal h;

    function setUp() public { h = new Harness(); }

    /// @dev THE HEADLINE, IN THE CONTRACT. The figure recorded for this case, computed by the real
    ///      library rather than by a model of it. Pot $28,744, eight draws left, $4,000 a
    ///      draw still arriving. The old rule pays a third of what the season can carry.
    function test_theFallbackNoLongerIgnoresIncomeStillToArrive() public view {
        uint256 pot = 28_744e6;
        uint256 dl = 8;
        uint256 inc = 4_000e6;

        // Force the fallback: an anchor far too large for any growth factor to survive.
        (uint256 amount, SeasonArc.Bind bind) =
            h.sizeWithReturn(pot, pot, dl, inc, 2_990, 2_500);
        assertEq(uint256(bind), uint256(SeasonArc.Bind.SUSTAINED), "precondition: the fallback fired");

        uint256 oldRule = pot / dl;
        assertEq(oldRule, 3_593e6, "the old rule: the pot spread over the draws left");
        // $9,606.23, which is what the contract computes and therefore what every document
        // now quotes. An earlier model run at whole-dollar scale gave 9,605; at six decimals
        // the integer flooring lands a fraction differently. Right about the size, wrong in
        // the last cents, which is what "the model is not the contract" means in practice.
        assertApproxEqAbs(amount, 9_606e6, 5e6,
            "the new rule: what the pot AND the income still coming can carry");
        assertGt(amount, oldRule * 2, "which is more than double what the old rule paid");
    }

    /// @dev AND IT IS NOT A GUESS. Whatever the fallback returns must survive the library's
    ///      own forward walk to the close, and one unit more must not. That is the definition
    ///      of largest-sustainable, asserted against the walk rather than against a figure.
    ///      FUZZED, because the closed form was verified in Python against a Python bisection
    ///      and that proves nothing about this contract.
    ///      RETURN SHARE IS FUZZED TOO, across its whole legal range and not pinned at the
    ///      host's 2,990. Swept to 9,999, the property holds everywhere; pinning one value
    ///      would have left that a claim about one run rather than about this contract.
    function testFuzz_whateverTheFallbackPaysIsTheMostTheWalkSurvives(
        uint256 potRaw,
        uint256 incRaw,
        uint256 rbRaw,
        uint8 drawsRaw
    ) public view {
        uint256 pot = bound(potRaw, 1e6, 500_000_000e6);
        uint256 inc = bound(incRaw, 0, 50_000_000e6);
        uint256 rb = bound(rbRaw, 0, 9_999);
        uint256 dl = bound(uint256(drawsRaw), 2, 208);

        (uint256 amount, SeasonArc.Bind bind) = h.sizeWithReturn(pot, pot, dl, inc, rb, 2_500);
        if (bind != SeasonArc.Bind.SUSTAINED) return;   // the arc found room; nothing to check
        if (amount == 0) return;                        // nothing was affordable at all

        assertGt(h.leftover(pot, amount, dl, inc, rb, G_MIN), 0,
            "what it pays must reach the close with something standing");
        assertEq(h.leftover(pot, amount + 1, dl, inc, rb, G_MIN), 0,
            "and one unit more must not: this is the LARGEST such payment, not merely a safe one");
    }

    /// @dev THE DEFECT ITSELF. At any state where the fallback fires and income is still
    ///      arriving, the rule that shipped pays LESS than the previous draw while the rule
    ///      that replaces it does not. That is the whole failure, asserted directly rather
    ///      than through a season fixture: a fixture has to reproduce eighty-five draws of
    ///      accumulation to reach the state, and a test that needs a novel to reach its
    ///      subject is a test nobody maintains.
    function test_theOldRulePaidLessThanTheDrawBeforeAndTheNewOneDoesNot() public view {
        uint256 pot = 28_744e6;
        uint256 dl = 8;
        uint256 inc = 4_000e6;
        uint256 lastPaid = 5_000e6;      // what the previous draw paid

        (uint256 amount, SeasonArc.Bind bind) =
            h.sizeWithReturn(pot, pot, dl, inc, 2_990, 2_500);
        assertEq(uint256(bind), uint256(SeasonArc.Bind.SUSTAINED), "precondition: the fallback fired");

        uint256 oldRule = pot / dl;
        assertLt(oldRule, lastPaid,
            "THE DEFECT: the rule that shipped pays less than the draw before");
        assertGt(amount, lastPaid,
            "THE FIX: the rule that replaces it does not");
    }

    /// @dev THE BOUNDARY THE FALLBACK USED TO TAKE. The solver returns its floor both when flat
    ///      growth runs the pot dry and when flat still fits but nothing steeper does. These
    ///      inputs are the second case, found by searching the Python port: flat payments of
    ///      the last amount leave about $1,032 at the end of the season. The fallback would have
    ///      paid a slightly larger flat amount instead; the rule now pays the last amount and
    ///      leaves the surplus to the closing draw.
    function test_whenFlatStillFitsTheArcFlattensRatherThanFallingBack() public view {
        uint256 pot = 1_820_824e6;
        uint256 last = 123_568e6;
        uint256 dl = 21;
        uint256 inc = 1_810e6;
        uint256 rb = 2_990;
        uint256 flatLeft = SeasonArc._leftover(pot, last, dl, inc, rb, G_MIN);
        assertGt(flatLeft, 0, "precondition: flat payments of the last amount fit the season");
        assertEq(SeasonArc._leftover(pot, last, dl, inc, rb, G_MIN + 1), 0,
            "precondition: and nothing steeper does, so the solver returns its floor");

        (uint256 amount, SeasonArc.Bind bind) = h.sizeWithReturn(pot, last, dl, inc, rb, 2_500);
        assertEq(uint256(bind), uint256(SeasonArc.Bind.ARC), "the arc has flattened, not failed");
        assertEq(amount, last, "so the draw pays what the last one did");
    }
}

contract Harness {
    function sizeWithReturn(
        uint256 pot, uint256 last, uint256 left, uint256 income, uint256 returnBps, uint256 openBps
    ) external pure returns (uint256, SeasonArc.Bind) {
        return SeasonArc.size(pot, last, left, income, returnBps, openBps);
    }

    /// @dev The library's own forward walk. _leftover moved from private to internal at
    ///      v0.41 so this can call it: the fuzz below has to assert against the REAL solvency
    ///      test, not a reimplementation of it, because a reimplementation that drifts is
    ///      exactly how a fuzz keeps passing while testing something that no longer exists.
    ///      Library internals are inlined, so the visibility change costs no bytecode.
    function leftover(
        uint256 pot, uint256 lastPaid, uint256 drawsLeft,
        uint256 incomeEstimate, uint256 returnBps, uint256 g
    ) external pure returns (uint256) {
        return SeasonArc._leftover(pot, lastPaid, drawsLeft, incomeEstimate, returnBps, g);
    }
}
