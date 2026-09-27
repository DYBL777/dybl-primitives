// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

/// @notice A literal week-by-week walkthrough of the opening weeks with an 80% user crash
///         at draw 3, run at the fixture's 25% floor.
contract HandRun is Base {
    BreathHost internal n;
    uint256 internal pot;
    uint256 internal roll;
    uint256 internal prev;

    function _cfg25() internal pure returns (Breath.Config memory c) {
        c = defaultConfig();    // the fixture's 25% floor and 40 bps creep
    }

    function _draw(uint256 wk, uint256 income) internal {
        pot += income;
        uint256 y = pot / 1040;                       // ~5% APY for one week
        pot += y;
        n.observe(income);
        (uint256 amt, Breath.Bind bind) = n.quote(pot, y, RHO);
        emit log_named_uint("week", wk);
        emit log_named_uint("  income this week", income / 1e6);
        emit log_named_uint("  pot available", pot / 1e6);
        emit log_named_uint("  PRIZE", amt / 1e6);
        emit log_named_uint("  prize as % of income", income == 0 ? 0 : (amt * 100) / income);
        emit log_named_uint("  bind", uint256(bind));
        if (prev > 0) {
            emit log_named_int("  change vs last week %",
                int256((amt * 100) / prev) - 100);
        }
        if (amt > 0) {
            // reseed 20% returns; on a jackpot miss 30% of the 38% slice returns, 40% rolls
            uint256 back = (amt * 2000) / 10000 + (((amt * 3800) / 10000) * 3000) / 10000;
            roll += (((amt * 3800) / 10000) * 4000) / 10000;
            pot = pot - amt + back;
            n.commit(amt);
            prev = amt;
        }
        emit log_named_uint("  pot carried to next week", pot / 1e6);
    }

    function test_handRunWithCrashAtDrawThree() public {
        n = new BreathHost(_cfg25());
        pot = 0; roll = 0; prev = 0;
        _draw(1, INCOME);            // 1M users
        _draw(2, INCOME);            // 1M users
        _draw(3, INCOME / 5);        // 80% of users gone
        _draw(4, INCOME / 5);
        _draw(5, INCOME / 5);
        _draw(6, INCOME / 5);
        emit log_named_uint("jackpot roll held aside", roll / 1e6);
    }
}
