// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SeasonArc} from "../src/SeasonArc.sol";

/// @notice THE SMALLEST GAME THAT CAN RUN A SEASON ON SEASONARC. It holds a pot, takes some
///         income each draw, asks the library what to pay, pays it, and takes the returned
///         share back, until the last draw. No tickets, no randomness, no winners: those are a
///         host's business, and this exists so the library's season-long behaviour can be
///         watched without one.
/// @dev    What it does the way a real host does: the income lands in the pot before the
///         library is asked, the income it forecasts is the income it just saw, and a share of
///         every payment except the last comes back to the pot. What it leaves out: a real host
///         scales the last payment by the change in its field before asking, and withholds
///         from the closing draw as well. Neither is needed to test the library, and the
///         second is why a real host's pot does not end at exactly zero.
contract StandInGame {
    uint256 internal constant BPS = 10_000;

    uint256 public immutable DRAWS;
    uint256 public immutable OPENING_BPS;
    uint256 public immutable RETURN_BPS;

    uint256 public pot;
    uint256 public lastPaid;
    uint256 public drawsDone;
    uint256[] public paid;

    error SeasonOver();

    constructor(uint256 draws, uint256 openingBps, uint256 returnBps) {
        DRAWS = draws;
        OPENING_BPS = openingBps;
        RETURN_BPS = returnBps;
    }

    /// @notice Runs one draw on `income` of new money and returns what it paid.
    function draw(uint256 income) external returns (uint256 amount, SeasonArc.Bind bind) {
        if (drawsDone == DRAWS) revert SeasonOver();
        pot += income;
        uint256 potBefore = pot;
        (amount, bind) = SeasonArc.size(pot, lastPaid, DRAWS - drawsDone, income, RETURN_BPS, OPENING_BPS);
        // Checked arithmetic: a payment larger than the pot reverts here, which is what the
        // tests rely on to catch one.
        pot = potBefore - amount;
        drawsDone += 1;
        if (drawsDone < DRAWS) pot += (amount * RETURN_BPS) / BPS;
        lastPaid = amount;
        paid.push(amount);
    }

    function paidCount() external view returns (uint256) { return paid.length; }
}
