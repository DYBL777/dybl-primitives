// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Test} from "forge-std/Test.sol";
import {BreathEngine} from "../../src/lib/BreathEngineV13.sol";

/// @dev FIDELITY: the library v1.3 vs a pure replica of BullsEthCRE v1.17's solver,
///      copied verbatim from _simGeomPot/_solveGeometricBps with events stripped and
///      SEED_BPS/rails passed as parameters. If the library is true to the game, the two
///      must agree everywhere except the single documented boundary (worstCase == floor).
contract BreathEngineFidelityTest is Test {

    uint256 constant GEOM_SOLVER_ITERS = 24;

    // ── Verbatim BullsEthCRE v1.17 _simGeomPot (SEED_BPS parameterised) ──
    function monolithSim(uint256 pot, uint256 breathBps, uint256 n, uint256 revPerDraw, uint256 seedBps)
        internal pure returns (uint256)
    {
        for (uint256 i = 0; i < n; i++) {
            uint256 lost = pot * breathBps * (10000 - seedBps) / 100_000_000;
            pot = pot > lost ? pot - lost : 0;
            pot += revPerDraw;
        }
        return pot;
    }

    // ── Verbatim BullsEthCRE v1.17 _solveGeometricBps (events stripped, rails as params) ──
    function monolithSolve(uint256 pot, uint256 drawsLeft, uint256 floorV, uint256 revPerDraw,
                           uint256 seedBps, uint256 railMin, uint256 railMax)
        internal pure returns (uint256)
    {
        if (drawsLeft == 0 || pot == 0) return 0;
        uint256 projEnd = pot + revPerDraw * drawsLeft;
        if (projEnd <= floorV) return 0;             // monolith: <= (equality = distress)
        uint256 lo = 0;
        uint256 hi = railMax;
        for (uint256 i = 0; i < GEOM_SOLVER_ITERS; i++) {
            uint256 mid = (lo + hi + 1) / 2;
            if (monolithSim(pot, mid, drawsLeft, revPerDraw, seedBps) >= floorV) { lo = mid; } else { hi = mid - 1; }
        }
        if (lo < railMin) return lo;                 // H-06 rail release: honour the sub-rail answer
        if (lo > railMax) return railMax;
        return lo;
    }

    /// The head-to-head: identical answers everywhere except worstCase == floor exactly,
    /// where the divergence must be exactly the documented one (monolith 0, library floor-safe).
    function testFuzz_Fidelity_LibraryMatchesBullsEthSolver(
        uint96 pot_, uint96 floor_, uint8 draws_, uint96 rev_, uint16 seed_, uint16 railMax_
    ) public pure {
        uint256 pot = uint256(pot_) + 1;
        uint256 floorV = uint256(floor_);
        uint256 draws = (uint256(draws_) % 29) + 1;        // monolith's structural domain
        uint256 rev = uint256(rev_);
        uint256 seedBps = uint256(seed_) % 10000;          // BullsEth uses 1000; fuzz the family
        uint256 railMax = (uint256(railMax_) % 10000) + 1;

        uint256 libAnswer = BreathEngine.solve(pot, floorV, draws, rev, seedBps, railMax);
        uint256 monAnswer = monolithSolve(pot, draws, floorV, rev, seedBps, 100, railMax);
        uint256 worstCase = BreathEngine.sim(pot, 0, draws, rev, seedBps);

        if (worstCase == floorV && floorV != 0) {
            // The single documented boundary: monolith calls it distress, library searches.
            assertEq(monAnswer, 0, "monolith treats exact equality as insolvent");
            assertGe(BreathEngine.sim(pot, libAnswer, draws, rev, seedBps), floorV, "library stays floor-safe");
        } else {
            assertEq(libAnswer, monAnswer, "solver answers diverge outside the documented boundary");
        }
    }

    /// BullsEth's exact production parameters: SEED_BPS 1000, rails 100/1500, 29 draws.
    function testFuzz_Fidelity_AtBullsEthProductionParams(uint96 pot_, uint96 floor_, uint8 draws_, uint96 rev_) public pure {
        uint256 pot = uint256(pot_) + 1;
        uint256 floorV = uint256(floor_);
        uint256 draws = (uint256(draws_) % 29) + 1;
        uint256 rev = uint256(rev_);
        uint256 libAnswer = BreathEngine.solve(pot, floorV, draws, rev, 1000, 1500);
        uint256 monAnswer = monolithSolve(pot, draws, floorV, rev, 1000, 100, 1500);
        uint256 worstCase = BreathEngine.sim(pot, 0, draws, rev, 1000);
        if (worstCase == floorV && floorV != 0) {
            assertEq(monAnswer, 0, "boundary");
        } else {
            assertEq(libAnswer, monAnswer, "diverged at BullsEth production parameters");
        }
    }

    /// isInsolvent agrees with the monolith's distress branch everywhere except equality.
    function testFuzz_Fidelity_InsolvencyPredicateMatchesDistressBranch(
        uint96 pot_, uint96 floor_, uint8 draws_, uint96 rev_
    ) public pure {
        uint256 pot = uint256(pot_) + 1;
        uint256 floorV = uint256(floor_);
        uint256 draws = (uint256(draws_) % 29) + 1;
        uint256 rev = uint256(rev_);
        bool libInsolvent = BreathEngine.isInsolvent(pot, floorV, draws, rev, 0);
        uint256 projEnd = pot + rev * draws;               // monolith's linear projection, seed 0
        bool monDistress = projEnd <= floorV;
        if (projEnd == floorV) {
            assertFalse(libInsolvent, "library: exact equality is solvent");
            assertTrue(monDistress, "monolith: exact equality is distress");
        } else {
            assertEq(libInsolvent, monDistress, "predicates diverge off-boundary");
        }
    }

    /// The v1.3 helper, both directions, deterministic.
    function test_IsInsolvent_BothDirections() public pure {
        assertTrue(BreathEngine.isInsolvent(100e6, 200e6, 5, 0, 0), "cannot reach 2x with no revenue");
        assertFalse(BreathEngine.isInsolvent(100e6, 100e6, 5, 0, 0), "at-floor with rate 0 is solvent");
        assertFalse(BreathEngine.isInsolvent(100e6, 150e6, 5, 20e6, 0), "revenue reaches the floor");
    }
}
