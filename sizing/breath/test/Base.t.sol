// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Breath} from "../src/Breath.sol";

/// @notice Thin host exposing the library so tests exercise real storage and real EVM
///         execution rather than a pure-function stand-in.
contract BreathHost {
    using Breath for Breath.State;

    Breath.State  public bs;
    Breath.Config public cfg;

    constructor(Breath.Config memory c) { Breath.validate(c); cfg = c; }

    function observe(uint256 net) external { bs.observe(cfg, net); }

    function quote(uint256 pot, uint256 yieldWk, uint256 rhoBps)
        external view returns (uint256 amount, Breath.Bind bind)
    { return bs.payout(cfg, pot, yieldWk, rhoBps); }

    function commit(uint256 paid) external { bs.commit(paid); }

    /// @notice What a host channel could take on top, given this draw's prize.
    function spare(uint256 pot, uint256 weeklyPrize, uint256 maxShareBps)
        external view returns (uint256)
    { return Breath.spare(cfg, pot, weeklyPrize, maxShareBps); }

    function setLastPaid(uint256 v) external { bs.lastPaid = v; }
    function lastPaid() external view returns (uint256) { return bs.lastPaid; }
    function fast() external view returns (uint256) { return bs.fast; }
    function slow() external view returns (uint256) { return bs.slow; }
}

/// @notice Shared fixture. Deployment dials live in exactly one place.
abstract contract Base is Test {
    BreathHost internal h;

    uint256 internal constant USDC   = 1e6;
    uint256 internal constant INCOME = 4_000_000 * USDC;  // 1M tickets, $5, 20% treasury
    // DERIVED, NOT REMEMBERED. Rho returns the reseed share as a FLOOR and adds the share of
    // missed jackpots that routes back to the pot, so a value below the reseed floor is one
    // the live game cannot produce. This constant was 1,990 against a 2,000 floor, which made
    // every breakeven in the Breath-only battery run about 12% low: those figures were shifted
    // rather than wrong, since a smaller recycled share sizes smaller prizes, but they were
    // not the shipped game's figures. Recomputed here from the split so it cannot drift again:
    //   floor + jackpotBps * missToPotBps * missRate, all in bps.
    // At the shipped split (2,000 floor, 3,300 jackpot, 3,000 miss-to-pot) and the ~83% miss
    // rate a million-ticket field produces, that is 2,000 + 3,300*3,000*8,300/1e8 = 2,822.
    uint256 internal constant MISS_RATE_BPS = 8_300;      // ~83%, uniform picks at 1M tickets
    uint256 internal constant RHO =
        2_000 + (3_300 * 3_000 * MISS_RATE_BPS) / (10_000 * 10_000);

    function defaultConfig() internal pure returns (Breath.Config memory) {
        return Breath.Config({
            slowAlphaBps:  385,    // ~52 draws
            fastDownBps:  5000,    // ~3 draws, quick on the way down
            fastUpBps:    1820,    // ~10 draws, slower on the way up
            floorBps:     2500,    // week one pays 25% of income
            creepBps:       40,    // 0.4% of the slow average per draw. Paired with the
                                   // 25% floor this reaches income parity at year 3.6 at any SIZE,
                                   // on a FLAT crowd. A growing crowd outruns the creep and
                                   // banks the difference in the reserve instead. At ANY
                                   // scale: 10k users or 5M, the arc is identical because
                                   // both the floor and the creep are shares of live income.
                                   // The earlier 16 was calibrated against a 55% floor and
                                   // is wrong for this one.
            paceMinBps:   8500,
            paceMaxBps:   9500,
            trendLoBps:   9000,
            trendHiBps:  10200,
            riseBps:     12500,    // +25%
            fallBps:      9400,    // -6% per draw
            coverTarget:   40,     // hold the reserve at ~40 draws of the weekly prize
            spareShareBps: 2500,   // one ask may take a quarter of the surplus above it
            minDraw: uint128(1_000 * USDC)
        });
    }

    function setUp() public virtual {
        h = new BreathHost(defaultConfig());
    }

    /// @dev Warms the averages to a steady state at `income`.
    function settle(uint256 income, uint256 draws) internal {
        for (uint256 i = 0; i < draws; i++) h.observe(income);
    }
}
