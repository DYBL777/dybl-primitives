// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EternalSeed} from "../src/EternalSeed.sol";

/// @notice DOES EACH GAME'S OWN SEED LINE MATCH THE REFERENCE? The games write the seed rule
///         in a line of their own rather than calling this library. Each function below is that
///         line, copied from the named version of the game with its own constants, and each test
///         fuzzes it against seedReturn() and distributable().
/// @dev    A copy pins the line as it stood in that version. If a game changes its line, this
///         file does not notice until the copy is updated; each copy names its source so the
///         check can be repeated.
contract HostConformanceTest is Test {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant MAX_AMOUNT = type(uint256).max / BPS;

    // ─────────────────────────────────────────────────────────────────────────
    // THE LINES, AS WRITTEN IN EACH GAME
    // ─────────────────────────────────────────────────────────────────────────

    /// Lettery Perpetual 0.59, LetteryPerpetual.sol, the prize-sizing step:
    ///   currentSeedReturn = finaleRemaining > 0 ? 0 : (amount * split.reseedBps) / BPS;
    ///   tierPools[3] = amount - currentSeedReturn - tierPools[0] - tierPools[1] - tierPools[2];
    /// The tiers take the rest, the last by remainder, so prize money is amount minus the seed.
    function _perp(uint256 amount, uint256 reseedBps, bool countdown)
        internal pure returns (uint256 seed, uint256 prizes)
    {
        seed = countdown ? 0 : (amount * reseedBps) / BPS;
        prizes = amount - seed;
    }

    /// Lettery TF 1.2.1, LetteryTF.sol, the prize-sizing step (withheld on every draw):
    ///   currentSeedReturn = (amount * split.reseedBps) / BPS;
    function _tf(uint256 amount, uint256 reseedBps) internal pure returns (uint256 seed, uint256 prizes) {
        seed = (amount * reseedBps) / BPS;
        prizes = amount - seed;
    }

    /// BullsEthCRE 1.17, BullsEthCRE.sol, _calculatePrizePools:
    ///   currentDrawSeedReturn = weeklyPool * SEED_BPS / 10000;   (SEED_BPS = 1000)
    ///   distributable = weeklyPool - currentDrawSeedReturn - bonusContribution;
    /// The bonus is a second slice taken from what the seed leaves, outside the seed rule.
    function _bullsEth(uint256 weeklyPool) internal pure returns (uint256 seed, uint256 afterSeed) {
        seed = weeklyPool * 1000 / 10000;
        afterSeed = weeklyPool - seed;
    }

    /// SeedTogether 0.65, SeedTogether.sol, the draw request:
    ///   uint256 toPlayers = m == 1 ? payout : payout * PLAYER_BPS / BPS;   (PLAYER_BPS = 8000)
    ///   seedPot -= toPlayers;
    /// The players' share is rounded down and what is left stays in the pot as the seed.
    function _seedTogether(uint256 payout, bool finalDraw) internal pure returns (uint256 seed, uint256 prizes) {
        prizes = finalDraw ? payout : payout * 8_000 / BPS;
        seed = payout - prizes;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // THE CHECKS
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Lettery Perpetual matches the reference exactly, at any reseed share, and its
    ///         countdown draws match the reference at a seed share of zero.
    function testFuzz_perpetualMatches(uint256 amount, uint256 reseedBps, bool countdown) public pure {
        amount = bound(amount, 0, MAX_AMOUNT);
        reseedBps = bound(reseedBps, 0, BPS);
        uint256 s = countdown ? 0 : reseedBps;
        (uint256 seed, uint256 prizes) = _perp(amount, reseedBps, countdown);
        assertEq(seed, EternalSeed.seedReturn(amount, s), "seed");
        assertEq(prizes, EternalSeed.distributable(amount, s), "prizes");
    }

    /// @notice Lettery TF matches the reference exactly, at any reseed share.
    function testFuzz_tfMatches(uint256 amount, uint256 reseedBps) public pure {
        amount = bound(amount, 0, MAX_AMOUNT);
        reseedBps = bound(reseedBps, 0, BPS);
        (uint256 seed, uint256 prizes) = _tf(amount, reseedBps);
        assertEq(seed, EternalSeed.seedReturn(amount, reseedBps), "seed");
        assertEq(prizes, EternalSeed.distributable(amount, reseedBps), "prizes");
    }

    /// @notice BullsEthCRE's seed matches the reference exactly. What it distributes is the
    ///         reference's distributable less its separate bonus slice.
    function testFuzz_bullsEthMatches(uint256 weeklyPool) public pure {
        weeklyPool = bound(weeklyPool, 0, MAX_AMOUNT);
        (uint256 seed, uint256 afterSeed) = _bullsEth(weeklyPool);
        assertEq(seed, EternalSeed.seedReturn(weeklyPool, 1000), "seed");
        assertEq(afterSeed, EternalSeed.distributable(weeklyPool, 1000), "what the seed leaves");
    }

    /// @notice SeedTogether rounds the other way, as its KNOWN_ISSUES entry says: its seed is
    ///         the reference's seed or exactly one unit more, and it is one more exactly when
    ///         the payout times the seed share is not a whole multiple of 10,000. Both conserve
    ///         the payout. Its final draw matches the reference at a seed share of zero.
    function testFuzz_seedTogetherDiffersByTheKnownUnit(uint256 payout, bool finalDraw) public pure {
        payout = bound(payout, 0, MAX_AMOUNT);
        (uint256 seed, uint256 prizes) = _seedTogether(payout, finalDraw);
        assertEq(seed + prizes, payout, "conserves the payout");
        if (finalDraw) {
            assertEq(seed, EternalSeed.seedReturn(payout, 0), "final draw seeds nothing");
            return;
        }
        uint256 ref = EternalSeed.seedReturn(payout, 2_000);
        uint256 expectedGap = (payout * 2_000) % BPS == 0 ? 0 : 1;
        assertEq(seed - ref, expectedGap, "one unit more, exactly when there is a remainder");
    }

    /// @notice The gap in a worked case, so the direction is visible without a fuzzer.
    function test_seedTogetherWorkedExample() public pure {
        (uint256 seed, uint256 prizes) = _seedTogether(10_001, false);
        assertEq(seed, 2_001, "SeedTogether keeps the odd unit");
        assertEq(prizes, 8_000, "and pays 8,000");
        assertEq(EternalSeed.seedReturn(10_001, 2_000), 2_000, "the reference keeps 2,000");
        assertEq(EternalSeed.distributable(10_001, 2_000), 8_001, "and pays 8,001");
    }
}
