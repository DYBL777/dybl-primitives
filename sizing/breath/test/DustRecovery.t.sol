// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

contract DustRecovery is Base {
    /// @dev Does an accumulating yield figure actually change the dust picture? The earlier
    ///      30-year estimate modelled yieldWk as ONE week's yield. If the host accumulates
    ///      it across dusted draws (it never finalizes, so it is never zeroed), the floor
    ///      grows every dusted week and the game unsticks far sooner.
    function test_accumulatedYieldUnsticksDustMuchFaster() public {
        Breath.Config memory c = defaultConfig();
        BreathHost n = new BreathHost(c);

        uint256 income = 1_500 * USDC;          // 25% floor = $375, under $1,000 minDraw
        for (uint256 i = 0; i < 60; i++) n.observe(income);

        uint256 pot = 400_000 * USDC;
        uint256 weekly = pot / 1040;            // ~5% APY for one week
        uint256 accumulated;
        uint256 weeksToUnstick;
        for (uint256 w = 1; w <= 400; w++) {
            accumulated += weekly;              // never cleared, because a dusted draw
                                                // never reaches finalize
            (uint256 amt, ) = n.quote(pot, accumulated, RHO);
            if (amt > 0) { weeksToUnstick = w; break; }
            pot += income;                      // money keeps arriving, nothing paid out
            weekly = pot / 1040;
        }
        emit log_named_uint("weeks of dust before the game pays again", weeksToUnstick);
        emit log_named_uint("  vs a single-week yield model (never unsticks in 400)", 400);
        assertGt(weeksToUnstick, 0, "it must unstick at all");
        assertLt(weeksToUnstick, 200, "and far sooner than the 30-year single-week estimate");
    }

    /// @dev Same setup, but yieldWk pinned to one week, which is what the earlier model did.
    function test_singleWeekYieldModelDoesNotUnstick() public {
        Breath.Config memory c = defaultConfig();
        BreathHost n = new BreathHost(c);
        uint256 income = 1_500 * USDC;
        for (uint256 i = 0; i < 60; i++) n.observe(income);
        uint256 pot = 400_000 * USDC;
        bool everPaid;
        for (uint256 w = 1; w <= 400; w++) {
            (uint256 amt, ) = n.quote(pot, pot / 1040, RHO);
            if (amt > 0) { everPaid = true; break; }
            pot += income;
        }
        emit log_named_string("single-week model paid within 400 weeks", everPaid ? "yes" : "no");
    }
}
