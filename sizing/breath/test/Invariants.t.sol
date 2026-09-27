// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

/// @notice A minimal game around Breath, driven by the invariant runner. Each draw the pot earns
///         yield, the draw's income lands and is observed, Breath sizes the payout, the game
///         pays it and takes the returned share back. Income swings from nothing to three
///         times the usual; droughts and surges come in runs. Every rule the library states
///         about a single payout is checked on every draw, and a broken rule is recorded.
contract BreathHandler is Test {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant USDC = 1e6;
    uint256 internal constant USUAL = 40_000 * USDC;

    BreathHost public host;
    uint256 public immutable RHO;
    uint256 public immutable RISE;
    uint256 public immutable FALL;
    uint256 public immutable MIN_DRAW;

    uint256 public pot;
    uint256 public totalIn;      // income plus yield
    uint256 public totalOut;     // paid minus the share that came back
    uint256 public draws;

    // A rule broken on any draw, with the draw it broke on.
    bool public paidMoreThanPot;
    bool public paidDust;
    bool public broke_riseRail;
    bool public broke_fallRail;
    bool public zeroWithoutDust;
    uint256 public brokenAt;

    constructor(Breath.Config memory c, uint256 rho) {
        host = new BreathHost(c);
        RHO = rho;
        RISE = c.riseBps;
        FALL = c.fallBps;
        MIN_DRAW = c.minDraw;
    }

    function _draw(uint256 income, uint256 yieldBps) internal {
        uint256 y = (pot * yieldBps) / BPS;
        pot += y + income;
        totalIn += y + income;
        host.observe(income);

        uint256 last = host.lastPaid();
        (uint256 amount, Breath.Bind bind) = host.quote(pot, y, RHO);
        draws++;

        if (amount > pot) { paidMoreThanPot = true; brokenAt = draws; }
        if (amount != 0 && amount < MIN_DRAW) { paidDust = true; brokenAt = draws; }
        if ((amount == 0) != (bind == Breath.Bind.DUST)) { zeroWithoutDust = true; brokenAt = draws; }
        if (amount != 0 && last != 0) {
            if (amount > (last * RISE) / BPS) { broke_riseRail = true; brokenAt = draws; }
            if (bind != Breath.Bind.POT && amount < (last * FALL) / BPS) {
                broke_fallRail = true; brokenAt = draws;
            }
        }

        if (amount != 0) {
            uint256 back = (amount * RHO) / BPS;
            pot = pot - amount + back;
            totalOut += amount - back;
            host.commit(amount);
        }
    }

    /// One ordinary draw.
    function draw(uint256 incomeSeed, uint256 yieldSeed) external {
        _draw(bound(incomeSeed, 0, USUAL * 3), bound(yieldSeed, 0, 20));
    }

    /// A run of draws where income collapses to a sliver.
    function drought(uint8 lengthSeed, uint256 yieldSeed) external {
        uint256 n = bound(lengthSeed, 1, 15);
        uint256 yBps = bound(yieldSeed, 0, 20);
        for (uint256 i = 0; i < n; i++) _draw(USUAL / 100, yBps);
    }

    /// A run of draws where income surges.
    function surge(uint8 lengthSeed, uint256 yieldSeed) external {
        uint256 n = bound(lengthSeed, 1, 15);
        uint256 yBps = bound(yieldSeed, 0, 20);
        for (uint256 i = 0; i < n; i++) _draw(USUAL * 3, yBps);
    }
}

/// @notice Rules that hold after any sequence of draws, checked by Foundry's invariant runner.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 60
/// forge-config: default.invariant.fail-on-revert = true
contract BreathInvariants is Base {
    BreathHandler internal hd;

    function setUp() public override {
        hd = new BreathHandler(defaultConfig(), RHO);
        targetContract(address(hd));
    }

    /// @notice A payout is no larger than the pot it is drawn from.
    function invariant_noPayoutExceedsThePot() public view {
        assertFalse(hd.paidMoreThanPot(), "paid more than the pot");
    }

    /// @notice A payout is either nothing or at least minDraw, and nothing is reported as DUST.
    function invariant_noDustIsPaid() public view {
        assertFalse(hd.paidDust(), "paid a sliver under minDraw");
        assertFalse(hd.zeroWithoutDust(), "zero and DUST disagree");
    }

    /// @notice A payout rises no further in one draw than the rise rail allows.
    function invariant_theRiseRailHolds() public view {
        assertFalse(hd.broke_riseRail(), "rose past the rise rail");
    }

    /// @notice A payout falls no further than the fall rail allows, unless the pot itself ran
    ///         short (bind POT) or the draw paid nothing (the dust guard).
    function invariant_theFallRailHolds() public view {
        assertFalse(hd.broke_fallRail(), "fell past the fall rail");
    }

    /// @notice Every unit that came in, as income or yield, was paid out or is still in the pot.
    function invariant_everyUnitIsAccountedFor() public view {
        assertEq(hd.totalIn(), hd.totalOut() + hd.pot(), "accounting");
    }
}
