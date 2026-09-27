// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";
contract Sim is Test {
    uint256 constant RET = 2990;
    function _run(uint256[] memory tickets, uint256 draws, uint256 openBps)
        internal returns (uint256 first, uint256 last_, uint256 falls)
    {
        uint256 pot; uint256 last;
        for (uint256 d = 1; d <= draws; d++) {
            uint256 inc = tickets[d-1] * 5e6 * 8_000 / 10_000;   // $5 ticket, 20% treasury
            pot += inc;
            uint256 potBefore = pot;
            (uint256 a, ) = SeasonArc.size(pot, last, draws-d+1, inc, RET, openBps);
            if (d <= 10 || d == draws) {
                emit log_named_uint("draw", d);
                emit log_named_uint("   pot before ($)", potBefore/1e6);
                emit log_named_uint("   paid ($)", a/1e6);
                emit log_named_uint("   pct of pot (bps)", potBefore == 0 ? 0 : a*10_000/potBefore);
            }
            if (d == 1) first = a;
            if (last > 0 && a < last) falls++;
            last_ = a;
            pot -= a; if (draws-d+1 > 1) pot += a*RET/10_000; last = a;
        }
    }
    /// @dev What the reserve does when the crowd leaves: 100k a week, then 10k from draw 20.
    function test_crowdDropsAtDraw20() public {
        uint256[] memory t = new uint256[](52);
        for (uint256 i; i < 52; i++) t[i] = i < 19 ? 100_000 : 10_000;
        uint256 pot; uint256 last; uint256 worstAfterDrop = type(uint256).max;
        for (uint256 d = 1; d <= 52; d++) {
            uint256 inc = t[d-1] * 5e6 * 8_000 / 10_000;
            pot += inc;
            (uint256 a, ) = SeasonArc.size(pot, last, 52-d+1, inc, RET, 2_500);
            if (d >= 18 && d <= 24 || d == 30 || d == 40 || d == 52) {
                emit log_named_uint("draw", d);
                emit log_named_uint("   weekly income ($)", inc/1e6);
                emit log_named_uint("   paid ($)", a/1e6);
                emit log_named_uint("   paid as multiple of income (x100)", inc == 0 ? 0 : a*100/inc);
            }
            if (d >= 20 && a < worstAfterDrop) worstAfterDrop = a;
            pot -= a; if (52-d+1 > 1) pot += a*RET/10_000; last = a;
        }
        assertGt(worstAfterDrop, 200_000e6,
            "the reserve must carry the prize through a ninety per cent collapse");
    }

    /// @dev Not only a log dump: the shape it prints is asserted. Two earlier versions of
    ///      this file emitted numbers and passed unconditionally, and were counted among the
    ///      suite's tests.
    function test_flat100k_52draws() public {
        uint256[] memory t = new uint256[](52);
        for (uint256 i; i < 52; i++) t[i] = 100_000;
        (uint256 first, uint256 last_, uint256 falls) = _run(t, 52, 2_500);
        assertEq(falls, 0, "a flat season must not have a single down draw");
        assertGt(last_, first * 10, "and the closing draw must dwarf the opening");
    }
}
