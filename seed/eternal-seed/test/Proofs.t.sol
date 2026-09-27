// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EternalSeed} from "../src/EternalSeed.sol";

/// @notice Symbolic proofs, run with Halmos (`halmos`), not with `forge test`. Each `check_`
///         function is proved for every input in its stated range, not sampled like a fuzz
///         test; forge ignores them. Claims that need the solver to reason through
///         multiplication and division together (for example that the seed is no larger than
///         the pool) did not finish in the solver's time limit and are covered by the fuzz and
///         invariant tests instead.
contract EternalSeedProofs is Test {
    uint256 internal constant D = 10_000;

    /// Formulation B conserves the pool exactly: seed plus distributable is the pool, for every
    /// pool below 2^128 and every rate, in range or not.
    function check_flowConservesThePool(uint256 w, uint256 s) public pure {
        vm.assume(w < 2 ** 128);
        assertEq(EternalSeed.seedReturn(w, s) + EternalSeed.distributable(w, s), w);
    }

    /// At or above 100% the rate clamps: the whole pool seeds and nothing is distributable.
    function check_flowClampsAtTheBoundary(uint256 w, uint256 s) public pure {
        vm.assume(s >= D);
        assertEq(EternalSeed.seedReturn(w, s), w);
        assertEq(EternalSeed.distributable(w, s), 0);
    }

    /// Formulation A: within the required ordering, headroom plus the current floor is exactly
    /// the pot, for every pot below 2^128.
    function check_headroomPlusFloorIsThePot(uint256 pot, uint256 p, uint256 m) public pure {
        vm.assume(pot < 2 ** 128);
        vm.assume(m <= D);
        vm.assume(p <= m);
        assertEq(EternalSeed.maxDistributable(pot, p, m) + EternalSeed.seedFloor(pot, p, m), pot);
    }
}
