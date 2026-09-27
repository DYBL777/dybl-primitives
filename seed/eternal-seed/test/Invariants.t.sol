// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StandInGame} from "./StandInGame.sol";

/// @notice Drives two stand-in games, one under each retention rule, with random sequences of
///         draws: income that varies from nothing to ten times the usual, runs of empty draws,
///         and seasons of any length the fuzzer chooses.
contract SeedHandler is Test {
    uint256 internal constant INCOME = 10_000e6;

    StandInGame public flow;
    StandInGame public floorGame;
    uint256 public draws;

    constructor() {
        flow = new StandInGame(StandInGame.Retention.FLOW, 500, 1_000, 0, 10);
        floorGame = new StandInGame(StandInGame.Retention.FLOOR, 1_000, 0, 1_000, 10);
    }

    /// One draw in both games with the same income.
    function draw(uint256 incomeSeed) external {
        uint256 income = bound(incomeSeed, 0, INCOME * 10);
        flow.draw(income);
        floorGame.draw(income);
        draws++;
    }

    /// A run of draws with no income at all.
    function drought(uint8 lengthSeed) external {
        uint256 n = bound(lengthSeed, 1, 20);
        for (uint256 i = 0; i < n; i++) {
            flow.draw(0);
            floorGame.draw(0);
        }
        draws += n;
    }
}

/// @notice Rules that hold after any sequence of draws, checked by Foundry's invariant runner.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 100
/// forge-config: default.invariant.fail-on-revert = true
contract SeedInvariants is Test {
    SeedHandler internal h;

    function setUp() public {
        h = new SeedHandler();
        targetContract(address(h));
    }

    /// @notice Every unit that came in, as income or yield, was paid out or is still in the pot.
    function invariant_everyUnitIsAccountedForUnderFlow() public view {
        StandInGame g = h.flow();
        assertEq(g.totalIncome() + g.totalYield(), g.totalPaid() + g.pot(), "flow accounting");
    }

    /// @notice The same under Floor.
    function invariant_everyUnitIsAccountedForUnderFloor() public view {
        StandInGame g = h.floorGame();
        assertEq(g.totalIncome() + g.totalYield(), g.totalPaid() + g.pot(), "floor accounting");
    }

    /// @notice Under Floor, run at its ceiling rate of 10% every draw, each draw leaves at least
    ///         nine tenths of the pot behind: the invariant floor. The game also reverts if a
    ///         draw breaches the floor, and fail-on-revert turns that into a failure here.
    function invariant_theFloorKeepsNineTenthsEachDraw() public view {
        StandInGame g = h.floorGame();
        uint256 before = g.pot() + g.lastPaid();
        assertGe(g.pot() * 10, before * 9, "at most a tenth paid per draw");
    }

    /// @notice Under Flow, a draw pays no more than the pool it was drawn from.
    function invariant_flowPaysNoMoreThanItsPool() public view {
        StandInGame g = h.flow();
        uint256 before = g.pot() + g.lastPaid();
        assertLe(g.lastPaid() * 10_000, before * 500, "paid no more than the 5% pool");
    }

    /// @notice Under Flow, the seed stays behind: a draw pays at most nine tenths of its pool,
    ///         plus the one unit rounding can add. Worked out here from the pool alone, not by
    ///         calling the library, so a library that pays away part of the seed fails it.
    function invariant_flowKeepsItsSeed() public view {
        StandInGame g = h.flow();
        uint256 pool = ((g.pot() + g.lastPaid()) * 500) / 10_000;
        assertLe(g.lastPaid() * 10, pool * 9 + 10, "paid away part of the seed");
    }
}
