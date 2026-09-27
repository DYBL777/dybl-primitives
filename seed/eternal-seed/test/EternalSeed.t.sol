// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EternalSeed} from "../src/EternalSeed.sol";

/// @notice Exposes the library's internal functions so a test can call them and observe reverts.
contract Harness {
    function maxDistributable(uint256 pot, uint256 p, uint256 m) external pure returns (uint256) {
        return EternalSeed.maxDistributable(pot, p, m);
    }

    function seedFloor(uint256 pot, uint256 p, uint256 m) external pure returns (uint256) {
        return EternalSeed.seedFloor(pot, p, m);
    }

    function seedReturn(uint256 w, uint256 s) external pure returns (uint256) {
        return EternalSeed.seedReturn(w, s);
    }

    function distributable(uint256 w, uint256 s) external pure returns (uint256) {
        return EternalSeed.distributable(w, s);
    }

    function projected(uint256 pot, uint256 b, uint256 s, uint256 d) external pure returns (uint256) {
        return EternalSeed.projectedSeedContribution(pot, b, s, d);
    }
}

/// @notice Tests for the claims the library's documentation makes. Each test names the claim
///         it checks, so a reader can match a sentence in the source to the test behind it.
contract EternalSeedTest is Test {
    uint256 internal constant D = 10_000;

    /// @dev Largest value a pot or pool may take here without pot * bps overflowing for any
    ///      bps up to D. Above it the library reverts on overflow, which is a different case
    ///      from the ones these tests describe.
    uint256 internal constant MAX_AMOUNT = type(uint256).max / D;

    Harness internal h;

    function setUp() public {
        h = new Harness();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FORMULATION B: CONSERVATION AND ROUNDING
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Claim: seedReturn + distributable == weeklyPool, for every rate including the
    ///         out-of-range ones, where the clamp applies.
    function testFuzz_conservationHoldsForEveryRate(uint256 w, uint256 s) public view {
        w = bound(w, 0, MAX_AMOUNT);
        assertEq(h.seedReturn(w, s) + h.distributable(w, s), w, "seed plus distributable is the pool");
    }

    /// @notice Claim: the worked example printed in distributable()'s documentation.
    function test_workedExampleFromTheDocumentation() public view {
        assertEq(h.seedReturn(10_001, 1_000), 1_000, "seed");
        assertEq(h.distributable(10_001, 1_000), 9_001, "distributable");
        assertEq(uint256(10_001) * (D - 1_000) / D, 9_000, "the closed form loses a wei");
    }

    /// @notice Claim: the single-fraction closed form weeklyPool * (D - seedBps) / D returns
    ///         exactly 1 less than distributable() when weeklyPool * seedBps is not a multiple
    ///         of D, and the same value when it is.
    function testFuzz_distributableClosedFormGapIsExactlyOneOrZero(uint256 w, uint256 s) public view {
        w = bound(w, 0, MAX_AMOUNT);
        s = bound(s, 0, D - 1);
        uint256 closed = w * (D - s) / D;
        uint256 expected = (w * s) % D == 0 ? 0 : 1;
        assertEq(h.distributable(w, s) - closed, expected, "gap");
    }

    /// @notice Claim: at or above D the rate clamps. The whole pool seeds, nothing is paid.
    function testFuzz_formulationBClampsAtTheBoundary(uint256 w, uint256 s) public view {
        s = bound(s, D, type(uint256).max);
        assertEq(h.seedReturn(w, s), w, "whole pool seeds");
        assertEq(h.distributable(w, s), 0, "nothing distributable");
    }

    /// @notice Claim: seed rounds down, so rounding dust goes to distribution.
    function testFuzz_roundingFavoursDistribution(uint256 w, uint256 s) public view {
        w = bound(w, 0, MAX_AMOUNT);
        s = bound(s, 0, D - 1);
        assertEq(h.seedReturn(w, s), w * s / D, "seed is the floored share");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FORMULATION A: THE TWO FLOORS
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Claim: seedFloor is the subtraction form, and the single-fraction closed form
    ///         pot * (D - maxPayoutBps + payoutBps) / D returns exactly 1 less when
    ///         pot * (maxPayoutBps - payoutBps) is not a multiple of D, and the same otherwise.
    function testFuzz_seedFloorClosedFormGapIsExactlyOneOrZero(uint256 pot, uint256 p, uint256 m) public view {
        pot = bound(pot, 0, MAX_AMOUNT);
        m = bound(m, 0, D);
        p = bound(p, 0, m);
        uint256 floor_ = h.seedFloor(pot, p, m);
        assertEq(floor_, pot - pot * (m - p) / D, "subtraction form");
        uint256 closed = pot * (D - m + p) / D;
        uint256 expected = (pot * (m - p)) % D == 0 ? 0 : 1;
        assertEq(floor_ - closed, expected, "gap");
    }

    /// @notice Claim: the invariant floor is seedFloor(pot, 0, maxPayoutBps), which equals
    ///         pot - pot * maxPayoutBps / D.
    function testFuzz_invariantFloorDefinition(uint256 pot, uint256 m) public view {
        pot = bound(pot, 0, MAX_AMOUNT);
        m = bound(m, 0, D);
        assertEq(h.seedFloor(pot, 0, m), pot - pot * m / D, "invariant floor");
    }

    /// @notice Claim: seedFloor MOVES with payoutBps (raising the rate raises it), so it is not
    ///         the protected minimum. It never falls below the invariant floor, and it is
    ///         strictly above it whenever the current rate is worth at least one unit.
    function testFuzz_seedFloorMovesWithTheRate(uint256 pot, uint256 p1, uint256 p2, uint256 m) public view {
        pot = bound(pot, 0, MAX_AMOUNT);
        m = bound(m, 0, D);
        p1 = bound(p1, 0, m);
        p2 = bound(p2, p1, m);
        uint256 invariant = h.seedFloor(pot, 0, m);
        assertLe(h.seedFloor(pot, p1, m), h.seedFloor(pot, p2, m), "raising the rate raises it");
        assertGe(h.seedFloor(pot, p1, m), invariant, "never below the invariant floor");
        if (pot * p1 >= D) {
            assertGt(h.seedFloor(pot, p1, m), invariant, "and genuinely above it at a real rate");
        }
    }

    /// @notice Claim: Formulation A reverts on an inverted ordering, payoutBps above
    ///         maxPayoutBps, through checked arithmetic.
    function testFuzz_formulationARevertsOnInvertedOrdering(uint256 pot, uint256 p, uint256 m) public {
        pot = bound(pot, 0, MAX_AMOUNT);
        m = bound(m, 0, D - 1);
        p = bound(p, m + 1, D);
        vm.expectRevert();
        h.maxDistributable(pot, p, m);
        vm.expectRevert();
        h.seedFloor(pot, p, m);
    }

    /// @notice Claim: with maxPayoutBps above D and the ordering intact, the case is surfaced
    ///         (maxDistributable exceeds pot and seedFloor reverts) exactly when
    ///         delta > D AND pot * (delta - D) >= D, where delta = maxPayoutBps - payoutBps.
    ///         Every other case is silent.
    function testFuzz_oversizedCeilingExactCondition(uint256 pot, uint256 p, uint256 m) public view {
        uint256 mMax = 10 * D;
        pot = bound(pot, 0, type(uint256).max / mMax);
        m = bound(m, D + 1, mMax);
        p = bound(p, 0, m);
        uint256 delta = m - p;
        bool predicted = delta > D && pot * (delta - D) >= D;

        assertEq(h.maxDistributable(pot, p, m) > pot, predicted, "maxDistributable exceeds pot");

        bool reverted;
        try h.seedFloor(pot, p, m) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertEq(reverted, predicted, "seedFloor reverts");
    }

    /// @notice The same claim at small pots, where the boundary is crossed on most runs. The
    ///         fuzz above draws mostly large pots and so mostly lands on one side of it.
    function testFuzz_oversizedCeilingExactConditionAtSmallPots(uint256 pot, uint256 p, uint256 m) public view {
        pot = bound(pot, 0, 3 * D);
        m = bound(m, D + 1, 3 * D);
        p = bound(p, 0, m);
        uint256 delta = m - p;
        bool predicted = delta > D && pot * (delta - D) >= D;

        bool reverted;
        try h.seedFloor(pot, p, m) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertEq(reverted, predicted, "seedFloor reverts");
    }

    /// @notice Claim: the three worked examples in the PARAMETER CONSTRAINT section.
    function test_oversizedCeilingWorkedExamples() public {
        // Small pots absorb even a large delta: pot 1, delta 10001.
        assertEq(h.maxDistributable(1, 0, 10_001), 1, "dust pot, maxDistributable");
        assertEq(h.seedFloor(1, 0, 10_001), 0, "dust pot, seedFloor silent");
        // A delta at or below D never trips it: maxPayoutBps 12000, payoutBps 3000.
        uint256 big = 1e30;
        assertLe(h.maxDistributable(big, 3_000, 12_000), big, "in-range delta at any pot");
        h.seedFloor(big, 3_000, 12_000); // silent: returns rather than reverting
        // A pot below D still reverts at a large enough delta: pot 5000, delta 20001.
        assertEq(h.maxDistributable(5_000, 0, 20_001), 10_000, "exceeds the pot");
        vm.expectRevert();
        h.seedFloor(5_000, 0, 20_001);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TOOLING HELPER
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Claim: the projection is the seed of one period's pool, times the draws.
    function testFuzz_projectionIsLinear(uint256 pot, uint256 b, uint256 s, uint256 d) public view {
        pot = bound(pot, 0, 1e30);
        b = bound(b, 0, D);
        s = bound(s, 0, D);
        d = bound(d, 0, 10_000);
        uint256 pool = pot * b / D;
        assertEq(h.projected(pot, b, s, d), h.seedReturn(pool, s) * d, "linear projection");
    }

    /// @notice Claim: draws is unbounded and seed * draws is a multiplication, so a
    ///         pathological input reverts under checked arithmetic rather than wrapping.
    function test_projectionOverflowReverts() public {
        vm.expectRevert();
        h.projected(1e30, D, D - 1, type(uint256).max);
    }
}
