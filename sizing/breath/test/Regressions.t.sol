// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

/// @notice Regression tests carried from the library's first host, each written to fail
///         against the behaviour it replaced.
contract Regressions is Base {

    /// @notice `spare` is a share of the surplus ABOVE the cover target, so however often it
    ///         is asked it does not pull the pot below that target. This is why the library
    ///         needs no separate hard floor under `spare`.
    function test_spareCannotDrainBelowTheCoverTarget() public {
        settle(INCOME, 60);
        uint256 weekly = 1_000_000 * USDC;
        uint256 reserve = 40 * weekly;                 // coverTarget in the fixture
        uint256 pot = reserve + 100_000_000 * USDC;    // a real surplus on top

        for (uint256 i = 0; i < 50; i++) {
            uint256 offer = h.spare(pot, weekly, 10_000);
            if (offer == 0) break;
            pot -= offer;
            assertGe(pot, reserve, "no sequence of asks may breach the cover target");
        }
        assertGe(pot, reserve, "and the reserve is still intact at the end");
    }

    /// @notice The ladder descends on its own, with no schedule written anywhere.
    function test_repeatedAsksDescendWithoutAHardcodedLadder() public {
        settle(INCOME, 60);
        uint256 weekly = 1_000_000 * USDC;
        uint256 pot = 40 * weekly + 100_000_000 * USDC;
        uint256 previous = type(uint256).max;
        uint256 asks;
        for (uint256 i = 0; i < 6; i++) {
            uint256 offer = h.spare(pot, weekly, 10_000);
            if (offer == 0) break;
            assertLt(offer, previous, "each ask must be smaller than the one before it");
            previous = offer;
            pot -= offer;
            asks++;
        }
        assertGt(asks, 3, "there must be a real run of descending offers to speak of");
    }

    /// @notice The dust deadlock. A floor computed on income alone can sit permanently
    ///         under minDraw, and because a dusted draw never commits, the next draw
    ///         computes the identical figure and dusts again, forever.
    /// @dev    Including this draw's yield lets a growing reserve lift the floor over the
    ///         threshold on its own, which is what breaks the deadlock.
    function test_yieldLiftsTheFloorOutOfADustDeadlock() public {
        // Runs on the ordinary fixture: nothing else in the library masks the deadlock.
        BreathHost n = new BreathHost(defaultConfig());

        uint256 tinyIncome = 1_500 * USDC;   // 25% floor = $375, under the $1,000 minDraw
        for (uint256 i = 0; i < 60; i++) n.observe(tinyIncome);

        (uint256 noYield, Breath.Bind b1) = n.quote(2_700_000 * USDC, 0, RHO);
        assertEq(uint256(b1), uint256(Breath.Bind.DUST), "income alone cannot clear minDraw");
        assertEq(noYield, 0, "so the draw pays nothing, and never commits, so it repeats");

        // ~5% APY on a $2.7M reserve. Counting it in the floor is what lifts the game back
        // over the threshold on its own. The reserve has to be larger than it was at a 55%
        // floor, because a quarter of income plus yield is a smaller number than half of it:
        // the safer opening share is also the slower cure, which is the trade.
        (uint256 withYield, Breath.Bind b2) = n.quote(2_700_000 * USDC, 2_600 * USDC, RHO);
        assertGt(withYield, 0, "the reserve lifts the floor over the threshold");
        assertTrue(b2 != Breath.Bind.DUST, "and the game restarts itself");
    }

}
