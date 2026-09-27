// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

/// @notice The rails: how far a payout may move in one draw, and what may cut past them.
/// @dev    Two findings are asserted here: a payout may sit above breakeven while the fall
///         rail glides it down, and a collapse in income does not by itself cut harder than
///         the rail. The two exceptions, an empty pot and the dust guard, are pinned too.
contract Rails is Base {

    /// @notice GLIDE BEATS JUMP. A collapse in income, with a fat pot, holds the payout at the
    ///         fall rail. The two cases that cut harder, the dust guard and a short pot, are
    ///         pinned by the next two tests.
    function test_aCollapseHoldsAtTheFallRail() public {
        settle(INCOME, 60);
        h.setLastPaid(4_000_000 * USDC);
        for (uint256 i = 0; i < 6; i++) h.observe(INCOME / 500);   // income collapses

        uint256 railFloor = (4_000_000 * USDC * 9_400) / 10_000;
        (uint256 amt, Breath.Bind bind) = h.quote(200_000_000 * USDC, 0, RHO);
        assertEq(amt, railFloor, "a fat pot must hold the glide exactly at the rail");
        assertEq(uint256(bind), uint256(Breath.Bind.FALL_RAIL), "and the rail is what bound it");
    }

    /// @notice THE DUST GUARD IS THE OTHER EXCEPTION. A draw whose railed amount lands under
    ///         minDraw pays nothing, even where the fall rail alone would have allowed a
    ///         payment. A host that wants the rail to hold at every size sets minDraw to zero.
    function test_theDustGuardCanCutBelowTheFallRail() public {
        Breath.Config memory c = defaultConfig();
        BreathHost n = new BreathHost(c);
        n.observe(10 * USDC);                               // income far below the last prize
        uint256 last = (uint256(c.minDraw) * 105) / 100;    // last draw paid just above minDraw
        n.commit(last);
        assertLt((last * c.fallBps) / 10_000, c.minDraw, "precondition: the rail lands under minDraw");
        (uint256 amount, Breath.Bind bind) = n.quote(1_000_000 * USDC, 0, RHO);
        assertEq(amount, 0, "the draw pays nothing");
        assertEq(uint256(bind), uint256(Breath.Bind.DUST), "and reports why");
    }

    /// @notice A short pot cuts harder than the rail: it pays what is there.
    function test_aShortPotCutsHarder() public {
        settle(INCOME, 60);
        h.setLastPaid(4_000_000 * USDC);
        for (uint256 i = 0; i < 6; i++) h.observe(INCOME / 500);

        uint256 thinPot = 2_000_000 * USDC;
        (uint256 amt, Breath.Bind bind) = h.quote(thinPot, 0, RHO);
        assertEq(uint256(bind), uint256(Breath.Bind.POT), "the pot is what cut it");
        assertEq(amt, thinPot, "and it pays what is actually there, not less");
    }

    /// @notice A glide may sit above breakeven. That is a deliberate, affordable drawdown.
    function test_theGlideMayPayAboveBreakeven() public {
        settle(INCOME, 60);
        h.setLastPaid(40_000_000 * USDC);
        (uint256 amt, Breath.Bind bind) = h.quote(400_000_000 * USDC, 0, RHO);
        uint256 breakeven = (INCOME * 10_000) / (10_000 - RHO);
        assertEq(uint256(bind), uint256(Breath.Bind.FALL_RAIL), "the fall rail should bind");
        assertGt(amt, breakeven, "the glide is an affordable drawdown, not an income cap");
    }

    /// @notice Creep is capped by breakeven at every step, not merely collided with later.
    function testFuzz_creepNeverOutrunsBreakeven(uint96 potSeed) public {
        uint256 pot = 1_000_000 * USDC + (uint256(potSeed) % (900_000_000 * USDC));
        settle(INCOME, 60);
        uint256 breakeven = (INCOME * 10_000) / (10_000 - RHO);
        for (uint256 i = 0; i < 200; i++) {
            (uint256 amt, Breath.Bind bind) = h.quote(pot, 0, RHO);
            if (bind == Breath.Bind.DUST) break;
            assertLe(amt, breakeven, "payout above breakeven with no rail holding it");
            h.commit(amt);
            h.observe(INCOME);
        }
    }
}
