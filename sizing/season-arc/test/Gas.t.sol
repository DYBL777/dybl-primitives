// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

contract GasHost {
    function size(uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret)
        external pure returns (uint256 a, SeasonArc.Bind b)
    { (a, b) = SeasonArc.size(pot, last, left, inc, ret, 2_500); }
}

/// @notice WHAT A CALL COSTS, measured through a host. Each draw's call is metered on its own;
///         the bounds asserted sit above what was measured, so a change that makes the solver
///         much dearer fails here. A season far longer than 52 draws costs proportionally more
///         on its early draws, and a host's caller has to be able to afford that.
contract Gas is Test {
    uint256 constant RET = 2_990;
    GasHost h;

    function setUp() public { h = new GasHost(); }

    /// A 52-draw season. Income is $5 a ticket less 20% to the treasury; `crowd` gives the
    /// tickets sold each draw. Returns the dearest single call, the draw it fell on, and the
    /// season's total.
    function season(uint256[] memory crowd) internal returns (uint256 dearest, uint256 at, uint256 total) {
        uint256 pot;
        uint256 last;
        for (uint256 d = 1; d <= 52; d++) {
            uint256 inc = crowd[d - 1] * 5e6 * 8_000 / 10_000;
            pot += inc;
            uint256 g0 = gasleft();
            (uint256 a,) = h.size(pot, last, 53 - d, inc, RET);
            uint256 used = g0 - gasleft();
            total += used;
            if (used > dearest) { dearest = used; at = d; }
            pot -= a;
            if (d < 52) pot += a * RET / 10_000;
            last = a;
        }
    }

    /// Flat income: the second draw, with 51 left, is the dearest call.
    function test_aFlatSeasonCostsWhatItIsMeasuredAt() public {
        uint256[] memory c = new uint256[](52);
        for (uint256 i; i < 52; i++) c[i] = 100_000;
        (uint256 dearest, uint256 at, uint256 total) = season(c);
        emit log_named_uint("dearest call (gas)", dearest);
        emit log_named_uint("on draw", at);
        emit log_named_uint("whole season (gas)", total);
        assertEq(at, 2, "the dearest call is the second draw");
        assertLt(dearest, 450_000, "the dearest call");
        assertLt(total, 12_000_000, "the whole season");
    }

    /// The crowd leaves at draw 10, so later draws go through the fallback, which runs the
    /// search and then the flat-payment formula.
    function test_aCollapsingSeasonCostsWhatItIsMeasuredAt() public {
        uint256[] memory c = new uint256[](52);
        for (uint256 i; i < 52; i++) c[i] = i < 9 ? 100_000 : 3_000;
        (uint256 dearest, uint256 at, uint256 total) = season(c);
        emit log_named_uint("dearest call (gas)", dearest);
        emit log_named_uint("on draw", at);
        emit log_named_uint("whole season (gas)", total);
        assertLt(dearest, 450_000, "the dearest call");
        assertLt(total, 12_000_000, "the whole season");
    }
}
