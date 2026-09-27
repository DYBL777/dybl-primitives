// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Test} from "forge-std/Test.sol";
import {BreathEngine} from "../src/BreathEngine.sol";

/// @dev Probes for the library's documented edge cases.
contract BreathEngineLibProbeTest is Test {

    /// The earlier documented distress pattern (rate==0 && stock>0 && periods>0 && max>0)
    /// OVER-FIRES. Construct a SOLVENT state (worstCase >= floor: distributing nothing
    /// reaches the floor) where the search still lands on 0 because even 1 bps breaches.
    function test_Probe_SolventZeroHeadroomReturnsZero_DistressPatternOverfires() public pure {
        uint256 stock = 1e12; uint256 floorV = 1e12; uint256 periods = 1; uint256 rev = 0;
        uint256 worst = BreathEngine.sim(stock, 0, periods, rev, 0);
        assertGe(worst, floorV, "NOT structurally insolvent: rate 0 reaches the floor");
        uint256 rate = BreathEngine.solve(stock, floorV, periods, rev, 0, 10000);
        assertEq(rate, 0, "yet solve returns 0: the documented host pattern would emit false distress");
    }

    /// Boundary divergence: worstCase == floor EXACTLY. The monolith's <= treats this as
    /// insolvent (returns 0 + distress); the library's < proceeds to search. Pin the
    /// library behaviour and that the floor guarantee still holds.
    function test_Probe_ExactBoundaryProceedsAndFloorHolds() public pure {
        uint256 stock = 5e11; uint256 periods = 3; uint256 rev = 1e9;
        uint256 floorV = BreathEngine.sim(stock, 0, periods, rev, 0); // worstCase == floor exactly
        uint256 rate = BreathEngine.solve(stock, floorV, periods, rev, 0, 10000);
        assertGe(BreathEngine.sim(stock, rate, periods, rev, 0), floorV, "returned rate never breaches the floor");
    }

    /// The core safety invariant, fuzzed: whatever solve returns, simulating it never
    /// lands below the floor (whenever the zero-rate projection could reach the floor).
    function testFuzz_Probe_SolveNeverBreachesTheFloor(
        uint96 stock_, uint96 floor_, uint8 periods_, uint96 rev_, uint16 seed_, uint16 maxB_
    ) public pure {
        uint256 stock = uint256(stock_) + 1;
        uint256 floorV = uint256(floor_);
        uint256 periods = (uint256(periods_) % 40) + 1;
        uint256 rev = uint256(rev_);
        uint256 seedBps = uint256(seed_) % 10000;
        uint256 maxB = uint256(maxB_) % 10001;
        uint256 rate = BreathEngine.solve(stock, floorV, periods, rev, seedBps, maxB);
        if (BreathEngine.sim(stock, 0, periods, rev, seedBps) >= floorV) {
            assertGe(BreathEngine.sim(stock, rate, periods, rev, seedBps), floorV, "floor breached");
        } else {
            assertEq(rate, 0, "insolvent must return 0");
        }
    }

    /// The answer is the LARGEST safe rate, not merely a safe one: whenever solve returns a
    /// rate below its ceiling on a solvent input, one basis point more breaches the floor.
    function testFuzz_Probe_SolveReturnsTheLargestSafeRate(
        uint96 stock_, uint96 floor_, uint8 periods_, uint96 rev_, uint16 seed_, uint16 maxB_
    ) public pure {
        uint256 stock = uint256(stock_) + 1;
        uint256 floorV = uint256(floor_);
        uint256 periods = (uint256(periods_) % 40) + 1;
        uint256 rev = uint256(rev_);
        uint256 seedBps = uint256(seed_) % 10000;
        uint256 maxB = uint256(maxB_) % 10001;
        if (BreathEngine.sim(stock, 0, periods, rev, seedBps) < floorV) return; // insolvent
        uint256 rate = BreathEngine.solve(stock, floorV, periods, rev, seedBps, maxB);
        assertGe(BreathEngine.sim(stock, rate, periods, rev, seedBps), floorV, "the answer is safe");
        if (rate < maxB) {
            assertLt(BreathEngine.sim(stock, rate + 1, periods, rev, seedBps), floorV,
                "and one basis point more is not");
        }
    }

    /// The insolvency guard in solve() is load-bearing: an insolvent input returns 0 rather
    /// than reverting, across the supported ceiling range and at the top of the convergence
    /// range. Without the guard the search would reach mid == 0 and underflow.
    function test_Probe_InsolventInputReturnsZeroAndDoesNotRevert() public pure {
        uint256 stock = 1e12; uint256 periods = 29; uint256 rev = 1e9; uint256 seedBps = 1000;
        uint256 floorV = BreathEngine.sim(stock, 0, periods, rev, seedBps) + 1; // unreachable
        assertTrue(BreathEngine.isInsolvent(stock, floorV, periods, rev, seedBps), "precondition");
        uint256[5] memory ceilings = [uint256(0), 1, 10000, (1 << 24) - 2, (1 << 24) - 1];
        for (uint256 i = 0; i < ceilings.length; i++) {
            assertEq(BreathEngine.solve(stock, floorV, periods, rev, seedBps, ceilings[i]), 0,
                "insolvent input returns 0");
        }
    }

    /// potHealth() floors its result, but a gate against a whole-number threshold gives the same
    /// answer as the exact ratio would: potHealth >= T exactly when stock * 10000 >= T * floor.
    function testFuzz_Probe_HealthGateMatchesTheExactRatio(uint96 stock_, uint96 floor_, uint16 t_) public pure {
        uint256 stock = uint256(stock_);
        uint256 floorV = uint256(floor_) + 1;          // floor 0 is the sentinel case
        uint256 t = uint256(t_);
        bool gate = BreathEngine.potHealth(stock, floorV) >= t;
        bool exact = stock * 10000 >= t * floorV;
        assertEq(gate, exact, "gate outcome matches the exact ratio");
    }

    /// Where paying nothing lands exactly on the floor and the stock is small enough that a
    /// 1 bps payment rounds to nothing, solve() returns a positive rate that still holds the
    /// floor. BullsEthCRE's own solver treats this exact-equality case as distress and returns
    /// 0; this is the one place the fidelity suite expects the two to differ.
    function test_Probe_TruncationAtExactEqualityReturnsAFreeRate() public pure {
        uint256 stock = 9999; uint256 periods = 1; uint256 rev = 0; uint256 seedBps = 0;
        uint256 floorV = BreathEngine.sim(stock, 0, periods, rev, seedBps);     // == stock
        uint256 rate = BreathEngine.solve(stock, floorV, periods, rev, seedBps, 10000);
        assertEq(rate, 1, "1 bps of 9,999 rounds to nothing, so it is free");
        assertEq(BreathEngine.sim(stock, rate, periods, rev, seedBps), floorV, "and the floor holds exactly");
        assertLt(BreathEngine.sim(stock, rate + 1, periods, rev, seedBps), floorV, "2 bps does not");
    }

    /// Gas scales linearly in periods, 25 sims per solve. Measure to substantiate the bound.
    function test_Probe_GasScalesLinearlyInPeriods() public {
        uint256 g0 = gasleft();
        BreathEngine.solve(1e12, 9e11, 29, 1e9, 1000, 10000);
        uint256 g29 = g0 - gasleft();
        g0 = gasleft();
        BreathEngine.solve(1e12, 9e11, 1000, 1e9, 1000, 10000);
        uint256 g1000 = g0 - gasleft();
        emit log_named_uint("solve gas at periods=29", g29);
        emit log_named_uint("solve gas at periods=1000", g1000);
        assertGt(g1000, g29 * 20, "linear scaling confirmed: unbounded periods is a gas hazard");
    }
}
