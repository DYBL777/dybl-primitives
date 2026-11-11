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

    /// Lettery TF 1.2.1, LetteryTF.sol, the prize-sizing step (withheld on every draw), and
    /// unchanged at 1.4.3:
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

    /// SeedTogether 0.73, SeedTogether.sol, _size:
    ///   s.toReserve = s.sized * RESEED_BPS / BPS;   (RESEED_BPS = 2000)
    ///   uint256 paid = s.sized - s.toReserve + out;
    /// A fifth of the amount sized is held back, rounded down, and the players take the rest
    /// (plus what the reserve releases, which is outside the seed rule). The closing draw holds
    /// nothing back.
    function _seedTogether(uint256 sized, bool finalDraw) internal pure returns (uint256 seed, uint256 prizes) {
        seed = finalDraw ? 0 : sized * 2_000 / BPS;
        prizes = sized - seed;
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

    /// @notice SeedTogether matches the reference exactly at its seed share of a fifth, and its
    ///         closing draw matches the reference at a seed share of zero.
    function testFuzz_seedTogetherMatches(uint256 sized, bool finalDraw) public pure {
        sized = bound(sized, 0, MAX_AMOUNT);
        uint256 s = finalDraw ? 0 : 2_000;
        (uint256 seed, uint256 prizes) = _seedTogether(sized, finalDraw);
        assertEq(seed, EternalSeed.seedReturn(sized, s), "seed");
        assertEq(prizes, EternalSeed.distributable(sized, s), "prizes");
    }

    /// @notice The rounding in a worked case: the odd unit goes to the players, as in the
    ///         reference. SeedTogether 0.65 kept it in the seed.
    function test_seedTogetherWorkedExample() public pure {
        (uint256 seed, uint256 prizes) = _seedTogether(10_001, false);
        assertEq(seed, 2_000, "SeedTogether holds back 2,000");
        assertEq(prizes, 8_001, "and pays 8,001");
        assertEq(EternalSeed.seedReturn(10_001, 2_000), seed, "the reference's seed");
        assertEq(EternalSeed.distributable(10_001, 2_000), prizes, "the reference's prizes");
    }
}
