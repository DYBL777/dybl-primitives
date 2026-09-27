// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EternalSeed} from "../src/EternalSeed.sol";

/// @notice THE SMALLEST GAME THAT CAN HOLD A POT UNDER THE SEED RULE. Each draw the pot earns
///         yield on what it held, the draw's income lands, and the game pays a share of the
///         pot, keeping the rest back under one of the two retention rules. No tickets, no
///         randomness, no winners: those are a host's business, and this exists so the rule's
///         effect on a pot can be watched over many draws without one.
/// @dev    FLOW: a pool of payoutBps of the pot is set aside for the draw, and seedBps of that
///         pool comes back to the pot (seedReturn); the rest is paid (distributable).
///         FLOOR: payoutBps of the pot is paid, and the invariant floor, the part no rate up to
///         maxPayoutBps could reach this draw, is checked to have stayed in the pot.
///         Yield is earned on the balance held through the week, before that draw's income
///         lands, so a game that holds no pot earns none.
contract StandInGame {
    uint256 internal constant BPS = 10_000;

    enum Retention { FLOW, FLOOR }

    Retention public immutable MODE;
    uint256 public immutable PAYOUT_BPS;
    uint256 public immutable SEED_BPS;      // FLOW only
    uint256 public immutable MAX_PAYOUT_BPS; // FLOOR only
    uint256 public immutable YIELD_BPS;     // per draw, on the balance held

    uint256 public pot;
    uint256 public lastPaid;
    uint256 public totalIncome;
    uint256 public totalYield;
    uint256 public totalPaid;

    error FloorBreached();

    constructor(Retention mode, uint256 payoutBps, uint256 seedBps, uint256 maxPayoutBps, uint256 yieldBps) {
        MODE = mode;
        PAYOUT_BPS = payoutBps;
        SEED_BPS = seedBps;
        MAX_PAYOUT_BPS = maxPayoutBps;
        YIELD_BPS = yieldBps;
    }

    /// @notice Run one draw with this much new income. Returns what the draw paid.
    function draw(uint256 income) external returns (uint256 paid) {
        uint256 y = (pot * YIELD_BPS) / BPS;
        pot += y + income;
        totalYield += y;
        totalIncome += income;

        if (MODE == Retention.FLOW) {
            uint256 pool = (pot * PAYOUT_BPS) / BPS;
            paid = EternalSeed.distributable(pool, SEED_BPS);
        } else {
            paid = (pot * PAYOUT_BPS) / BPS;
            if (pot - paid < EternalSeed.seedFloor(pot, 0, MAX_PAYOUT_BPS)) revert FloorBreached();
        }

        pot -= paid;
        totalPaid += paid;
        lastPaid = paid;
    }
}
