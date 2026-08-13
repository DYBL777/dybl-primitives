// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Test} from "forge-std/Test.sol";
import {BreathEngine} from "../../src/lib/BreathEngineLib.sol";

/// @dev Audit probes for the standalone BreathEngine library v1.2.
contract BreathEngineLibProbeTest is Test {

    /// F-01: the documented distress pattern (rate==0 && stock>0 && periods>0 && max>0)
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

    /// F-02: gas scales linearly in periods, 24x per solve. Measure to substantiate the bound.
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
