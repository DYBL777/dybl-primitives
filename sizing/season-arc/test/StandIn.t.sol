// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";
import {StandInGame} from "./StandInGame.sol";

/// @notice WHOLE SEASONS THROUGH THE LIBRARY, on the stand-in game rather than a real host.
///         The unit tests pin single calls; these pin what the rule is for across a season:
///         payments rise, no draw pays more than the pot holds, the last draw takes what is
///         left, and a crowd that leaves is carried to the end rather than run dry.
contract StandInSeasons is Test {
    uint256 internal constant RET = 2_990;      // the return share Lettery TF passes
    uint256 internal constant OPENING = 2_500;  // and its opening share

    /// @dev A FLAT SEASON. The same income every draw for 52 draws. The first draw is the
    ///      opening share, every draw after it pays at least what the one before paid, the last
    ///      is the closing bind, and the pot ends empty. The closing-to-opening ratio is
    ///      measured in Ratio.t.sol; here it is only required to be a rise.
    function test_aFlatSeasonRisesAndEndsWithThePotSpent() public {
        StandInGame g = new StandInGame(52, OPENING, RET);
        uint256 prev;
        for (uint256 d = 1; d <= 52; d++) {
            (uint256 a, SeasonArc.Bind b) = g.draw(40_000e6);
            if (d == 1) {
                assertEq(uint256(b), uint256(SeasonArc.Bind.OPENING), "draw 1 is the opening");
                assertEq(a, 10_000e6, "and pays the opening share of a pot of 40,000");
            } else if (d == 52) {
                assertEq(uint256(b), uint256(SeasonArc.Bind.CLOSING), "draw 52 is the closing draw");
            } else {
                assertEq(uint256(b), uint256(SeasonArc.Bind.ARC), "every draw between is the solved arc");
            }
            assertGe(a, prev, "no draw pays less than the one before it");
            prev = a;
        }
        assertEq(g.pot(), 0, "the closing draw took what was left");
        assertGt(g.paid(51), g.paid(0) * 10, "and the season rose more than tenfold");
    }

    /// @dev A CROWD THAT LEAVES. Income falls 97% at draw 10. The payment steps down once, in
    ///      that week, and the rest of the season is carried flat by the sustained branch: no
    ///      draw pays nothing, and the pot still ends empty.
    function test_aCrowdThatLeavesStepsDownOnceAndIsCarriedToTheEnd() public {
        StandInGame g = new StandInGame(52, OPENING, RET);
        uint256 prev;
        uint256 falls;
        for (uint256 d = 1; d <= 52; d++) {
            (uint256 a,) = g.draw(d < 10 ? 40_000e6 : 1_200e6);
            assertGt(a, 0, "no draw pays nothing");
            if (d > 1 && a < prev) {
                falls++;
                assertEq(d, 10, "the only step down is in the week the crowd leaves");
            }
            prev = a;
        }
        assertEq(falls, 1, "one step down, not a slide");
        assertEq(g.pot(), 0, "and the pot still ends empty");
    }

    /// @dev ANY SEASON, ANY INCOME. Random length, opening share, return share and income
    ///      each draw, including draws with none. The stand-in subtracts each payment from the
    ///      pot with checked arithmetic, so a payment above the pot reverts the run; the test
    ///      requires every draw to complete and the pot to end empty.
    function testFuzz_noDrawPaysMoreThanThePotHolds(
        uint256 seed, uint256 draws, uint256 openingBps, uint256 returnBps
    ) public {
        draws = bound(draws, 2, 104);
        openingBps = bound(openingBps, 1_000, 5_000);
        returnBps = bound(returnBps, 0, 5_000);
        StandInGame g = new StandInGame(draws, openingBps, returnBps);
        for (uint256 d = 1; d <= draws; d++) {
            uint256 r = uint256(keccak256(abi.encode(seed, d)));
            uint256 income = r % 4 == 0 ? 0 : r % 1_000_000e6;
            uint256 potAfterIncome = g.pot() + income;
            (uint256 a,) = g.draw(income);
            assertLe(a, potAfterIncome, "a draw paid more than the pot held");
        }
        assertEq(g.drawsDone(), draws, "every draw ran");
        assertEq(g.pot(), 0, "and the closing draw took what was left");
    }

    function test_aSeasonCannotRunPastItsLastDraw() public {
        StandInGame g = new StandInGame(4, OPENING, RET);
        for (uint256 d = 0; d < 4; d++) g.draw(1_000e6);
        vm.expectRevert(StandInGame.SeasonOver.selector);
        g.draw(1_000e6);
    }
}
