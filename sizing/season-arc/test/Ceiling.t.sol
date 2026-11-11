// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, stdError} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";
import {ArcRule} from "./ArcRule.sol";

contract CeilingHost {
    function size(uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret)
        external pure returns (uint256 a, uint8 b)
    { SeasonArc.Bind bind; (a, bind) = SeasonArc.size(pot, last, left, inc, ret, 2_500); b = uint8(bind); }
}

/// @notice VERY LARGE FIGURES. The other fuzz tests keep pots under 5e14; these go from there to
///         1e60 (1e54 USDC, or 1e42 of an 18-decimal token) and judge each answer by the rule
///         coded apart (`ArcRule.sol`). Two pinned calls mark where the arithmetic stops: just
///         under it a call answers by the rule, and above it the call reverts on overflow
///         rather than answering wrongly (KNOWN_ISSUES).
contract Ceiling is Test {
    CeilingHost h;

    function setUp() public { h = new CeilingHost(); }

    function testFuzz_largeFiguresAnswerByTheRule(uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret)
        public view
    {
        pot = bound(pot, 5e14, 1e60);
        last = bound(last, 1, pot);
        left = bound(left, 2, 104);
        inc = bound(inc, 0, pot);
        ret = bound(ret, 0, 9_999);
        (uint256 amt, uint8 bind) = h.size(pot, last, left, inc, ret);
        string memory why = ArcRule.judge(pot, last, left, inc, ret, amt, bind);
        assertEq(bytes(why).length, 0, why);
    }

    /// A pot of 1e71 over 52 draws, with a last payment of a thousandth of it and a hundredth
    /// arriving each draw: answered, and by the rule.
    function test_justUnderTheCeilingTheCallAnswers() public view {
        uint256 pot = 1e71;
        (uint256 amt, uint8 bind) = h.size(pot, pot / 1_000, 52, pot / 100, 0);
        string memory why = ArcRule.judge(pot, pot / 1_000, 52, pot / 100, 0, amt, bind);
        assertEq(bytes(why).length, 0, why);
    }

    /// The same call at a pot of 1e72 overflows inside the search and reverts.
    function test_aboveTheCeilingTheCallReverts() public {
        uint256 pot = 1e72;
        vm.expectRevert(stdError.arithmeticError);
        h.size(pot, pot / 1_000, 52, pot / 100, 0);
    }
}
