// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BreathEngine} from "../src/BreathEngine.sol";

/// @notice Symbolic proofs, run with Halmos (`halmos`), not with `forge test`. Each `check_`
///         function is proved for every input in its stated range; forge ignores them. The
///         solver and its projection loop are too deep for a symbolic proof and are covered by
///         the fuzz, fidelity and invariant tests instead.
contract BreathEngineProofs is Test {
    /// The running average lands between the previous average and the new value.
    function check_averageStaysBetweenOldAndNew(uint256 prev, uint256 cur) public pure {
        vm.assume(prev < 2 ** 128 && cur < 2 ** 128);
        uint256 e = BreathEngine.updateEMA(prev, cur);
        uint256 lo = prev < cur ? prev : cur;
        uint256 hi = prev < cur ? cur : prev;
        assertGe(e, lo);
        assertLe(e, hi);
    }

    /// With no floor set, solve() returns the ceiling whenever there is stock and time left.
    function check_noFloorReturnsTheCeiling(uint256 stock, uint256 periods, uint256 maxB) public pure {
        vm.assume(stock > 0 && periods > 0);
        assertEq(BreathEngine.solve(stock, 0, periods, 0, 0, maxB), maxB);
    }

    /// potHealth() reports the no-obligation sentinel when the floor is zero.
    function check_healthSentinelWithNoFloor(uint256 stock) public pure {
        assertEq(BreathEngine.potHealth(stock, 0), type(uint256).max);
    }
}
