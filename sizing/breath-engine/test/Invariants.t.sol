// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {BreathEngine} from "../src/BreathEngine.sol";

/// @notice A season run on BreathEngine, driven by the invariant runner. Each period the game
///         asks solve() for a rate, pays out at that rate using the same single floored step
///         sim() models, and then receives its income. The income the game plans with is its
///         estimate; the income it actually receives is the estimate plus a random extra, which
///         may be nothing. When the season opens solvent, the floor is to be held to the end.
contract SeasonHandler is Test {
    uint256 internal constant D = 10_000;
    uint256 internal constant SEED_BPS = 1_000;
    uint256 internal constant MAX_RATE = 1_500;

    uint256 public stock;
    uint256 public floorV;
    uint256 public periodsLeft;
    uint256 public estimate;
    uint256 public seasons;

    bool public wentInsolvent;       // a solvent season became insolvent mid-way
    bool public endedBelowFloor;     // a season finished under its floor
    bool public rateBreachedModel;   // a returned rate failed its own projection

    constructor() {
        _newSeason(1e12, 0, 29, 1e9);
    }

    function _newSeason(uint256 s, uint256 floorShareBps, uint256 n, uint256 est) internal {
        stock = s;
        estimate = est;
        periodsLeft = n;
        // A floor the season can meet: a share of what paying nothing would reach.
        floorV = (BreathEngine.sim(s, 0, n, est, SEED_BPS) * floorShareBps) / D;
        seasons++;
    }

    /// Start a fresh season with random size, floor, length and income estimate.
    function startSeason(uint96 stockSeed, uint16 floorSeed, uint8 lenSeed, uint64 estSeed) external {
        _newSeason(
            bound(stockSeed, 1e6, 1e15),
            bound(floorSeed, 0, D),
            bound(lenSeed, 1, 60),
            bound(estSeed, 0, 1e12)
        );
    }

    /// Run one period: solve, pay at the solved rate, receive at least the estimate.
    function period(uint64 extraSeed) external {
        if (periodsLeft == 0) return;
        if (BreathEngine.isInsolvent(stock, floorV, periodsLeft, estimate, SEED_BPS)) {
            wentInsolvent = true;
            return;
        }
        uint256 rate = BreathEngine.solve(stock, floorV, periodsLeft, estimate, SEED_BPS, MAX_RATE);
        if (BreathEngine.sim(stock, rate, periodsLeft, estimate, SEED_BPS) < floorV) {
            rateBreachedModel = true;
        }
        uint256 lost = (stock * rate * (D - SEED_BPS)) / (D * D);
        stock = stock > lost ? stock - lost : 0;
        stock += estimate + bound(extraSeed, 0, estimate + 1e6);
        periodsLeft--;
        if (periodsLeft == 0 && stock < floorV) endedBelowFloor = true;
    }
}

/// @notice Rules that hold across whole seasons, checked by Foundry's invariant runner.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 80
/// forge-config: default.invariant.fail-on-revert = true
contract BreathEngineInvariants is Test {
    SeasonHandler internal h;

    function setUp() public {
        h = new SeasonHandler();
        targetContract(address(h));
    }

    /// @notice Every rate solve() returns passes its own projection.
    function invariant_everyRateHoldsTheFloorInTheModel() public view {
        assertFalse(h.rateBreachedModel(), "a returned rate breached the floor in sim()");
    }

    /// @notice A season that opens solvent, pays at the solved rate each period and receives at
    ///         least its estimated income stays solvent throughout.
    function invariant_aSolventSeasonStaysSolvent() public view {
        assertFalse(h.wentInsolvent(), "became insolvent mid-season");
    }

    /// @notice And it ends with the floor still in the pot.
    function invariant_theSeasonEndsAtOrAboveItsFloor() public view {
        assertFalse(h.endedBelowFloor(), "ended below the floor");
    }
}
