// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

/// @notice THE PACE AND THE CREEP, PINNED. When the breakeven cap binds, the payout is breakeven
///         times a pace set by the trend (fast average over slow): the band's low pace at or
///         under its low end, its high pace at or over its high end, and a straight line
///         between. When creep binds, the payout is the last one plus a share of the slow
///         average. Each test works the figure out from the averages by hand and checks the
///         library pays it.
contract Pace is Base {

    /// The target the rule gives for the averages the host holds now.
    function expected(BreathHost x, Breath.Config memory c, uint256 yieldWk)
        internal view returns (uint256 target, uint256 trend)
    {
        uint256 fast = x.fast();
        uint256 slow = x.slow();
        uint256 breakeven = ((fast + yieldWk) * 10_000) / (10_000 - RHO);
        trend = (fast * 10_000) / slow;
        uint256 pace;
        if (trend <= c.trendLoBps) pace = c.paceMinBps;
        else if (trend >= c.trendHiBps) pace = c.paceMaxBps;
        else pace = c.paceMinBps
            + ((uint256(c.paceMaxBps) - c.paceMinBps) * (trend - c.trendLoBps))
              / (uint256(c.trendHiBps) - c.trendLoBps);
        target = (breakeven * pace) / 10_000;
    }

    /// Sets the last payment just above the target, so creep wants more than breakeven allows
    /// and both rails sit either side of it; the breakeven cap is then what binds.
    function payAtTheCap(BreathHost x, uint256 target) internal returns (uint256 amount, Breath.Bind bind) {
        x.setLastPaid((target * 100) / 97);
        (amount, bind) = x.quote(1_000_000_000 * USDC, 0, RHO);
    }

    function test_aFallingTrendPaysTheLowPace() public {
        settle(INCOME, 60);
        for (uint256 i = 0; i < 4; i++) h.observe(INCOME / 3);
        Breath.Config memory c = defaultConfig();
        (uint256 target, uint256 trend) = expected(h, c, 0);
        assertLe(trend, c.trendLoBps, "the trend is at or under the band");
        (uint256 amount, Breath.Bind bind) = payAtTheCap(h, target);
        assertEq(uint256(bind), uint256(Breath.Bind.BREAKEVEN), "the cap binds");
        assertEq(amount, target, "breakeven at the low pace");
    }

    function test_aRisingTrendPaysTheHighPace() public {
        settle(INCOME, 60);
        for (uint256 i = 0; i < 4; i++) h.observe(INCOME * 2);
        Breath.Config memory c = defaultConfig();
        (uint256 target, uint256 trend) = expected(h, c, 0);
        assertGe(trend, c.trendHiBps, "the trend is at or over the band");
        (uint256 amount, Breath.Bind bind) = payAtTheCap(h, target);
        assertEq(uint256(bind), uint256(Breath.Bind.BREAKEVEN), "the cap binds");
        assertEq(amount, target, "breakeven at the high pace");
    }

    /// Inside the band the pace is interpolated. The band here is wide (5,000 to 12,000) and the
    /// pace range deep (3,000 to 9,500), so each difference in the line is more than its
    /// smaller term and a remainder would not stand in for it.
    function test_insideTheBandThePaceIsInterpolated() public {
        Breath.Config memory c = defaultConfig();
        c.paceMinBps = 3_000;
        c.trendLoBps = 5_000;
        c.trendHiBps = 12_000;
        BreathHost x = new BreathHost(c);
        for (uint256 i = 0; i < 60; i++) x.observe(INCOME);
        for (uint256 i = 0; i < 3; i++) x.observe((INCOME * 13) / 10);
        (uint256 target, uint256 trend) = expected(x, c, 0);
        assertGt(trend, c.trendLoBps, "the trend is inside the band");
        assertLt(trend, c.trendHiBps, "the trend is inside the band");
        assertGe(trend, 2 * uint256(c.trendLoBps), "and far enough above its low end");
        (uint256 amount, Breath.Bind bind) = payAtTheCap(x, target);
        assertEq(uint256(bind), uint256(Breath.Bind.BREAKEVEN), "the cap binds");
        assertEq(amount, target, "breakeven at the interpolated pace");
    }

    /// Well under the cap and over the floor, the payout is the last one plus the creep share
    /// of the slow average.
    function test_underTheCapThePayoutCreepsByItsShareOfTheSlowAverage() public {
        settle(INCOME, 60);
        Breath.Config memory c = defaultConfig();
        uint256 last = h.fast() / 2;
        h.setLastPaid(last);
        (uint256 amount, Breath.Bind bind) = h.quote(1_000_000_000 * USDC, 0, RHO);
        assertEq(uint256(bind), uint256(Breath.Bind.CREEP), "creep binds");
        assertEq(amount, last + (h.slow() * c.creepBps) / 10_000, "the last payout plus the creep share");
    }
}
