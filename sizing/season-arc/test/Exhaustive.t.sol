// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";
import {ArcRule} from "./ArcRule.sol";

contract GridHost {
    function size(uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret)
        external pure returns (uint256 a, uint8 b)
    { SeasonArc.Bind bind; (a, bind) = SeasonArc.size(pot, last, left, inc, ret, 2_500); b = uint8(bind); }
}

/// @notice EVERY INPUT ON A GRID, judged by the rule coded apart from the library
///         (`ArcRule.sol`). Each grid is 40 pots x 40 last payments x 5 incomes x 5 return
///         shares, 40,000 mid-season calls. The tiny grids (pots of 1 to 40 units) are where
///         rounding decides the answer and where most calls fall back to a flat payment; the
///         money grids (pots of 1,000 to 40,000 USDC) are where most calls follow the arc.
///
///         For every call: the payment is under the pot; an ARC payment comes from a growth
///         factor that survives the season, and no growth factor that would pay more survives;
///         a SUSTAINED payment comes only when flat at the last payment runs dry, survives the
///         season itself, and is the largest flat payment that does.
contract Exhaustive is Test {
    GridHost h;
    uint256 cases;
    uint256 arcs;
    uint256 sustained;

    function setUp() public { h = new GridHost(); }

    /// The grid, scaled: pot in units of potU, last payment in units of lastU, income in units
    /// of incU, plus an odd offset so rounding does not always land on a round number.
    function grid(uint256 left, uint256 potU, uint256 lastU, uint256 incU, uint256 jitter) internal {
        uint256[5] memory incs = [uint256(0), 1, 3, 10, 40];
        uint256[5] memory rets = [uint256(0), 1, 2_990, 5_000, 9_999];
        for (uint256 pot = 1; pot <= 40; pot++) {
            for (uint256 last = 1; last <= 40; last++) {
                for (uint256 a = 0; a < 5; a++) {
                    for (uint256 b = 0; b < 5; b++) {
                        uint256 p = pot * potU + jitter * pot;
                        uint256 l = last * lastU + jitter;
                        (uint256 amt, uint8 bind) = h.size(p, l, left, incs[a] * incU, rets[b]);
                        string memory why = ArcRule.judge(p, l, left, incs[a] * incU, rets[b], amt, bind);
                        assertEq(bytes(why).length, 0, why);
                        cases++;
                        if (bind == ArcRule.ARC) arcs++; else sustained++;
                    }
                }
            }
        }
        assertEq(cases, 40_000);
        emit log_named_uint("ARC", arcs);
        emit log_named_uint("SUSTAINED", sustained);
    }

    function test_tinyPotsTwoDrawsLeft() public { grid(2, 1, 1, 1, 0); }
    function test_tinyPotsThreeDrawsLeft() public { grid(3, 1, 1, 1, 0); }
    function test_tinyPotsFourDrawsLeft() public { grid(4, 1, 1, 1, 0); }
    function test_tinyPotsSixDrawsLeft() public { grid(6, 1, 1, 1, 0); }
    function test_tinyPotsTwelveDrawsLeft() public { grid(12, 1, 1, 1, 0); }

    /// Pots of 1,000 to 40,000 USDC, last payments of 50 to 2,000, income of 0 to 4,000 a draw.
    function test_moneyTwelveDrawsLeft() public { grid(12, 1_000e6, 50e6, 100e6, 7); }
    function test_moneyFiftyTwoDrawsLeft() public { grid(52, 1_000e6, 50e6, 100e6, 7); }
}
