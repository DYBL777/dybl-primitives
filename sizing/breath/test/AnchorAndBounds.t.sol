// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Breath} from "../src/Breath.sol";

/// @dev A thin host so the library can be driven directly. Breath's entry points take a
///      storage State, so they cannot be called from a pure test without one.
contract BreathDirectHost {
    using Breath for Breath.State;
    Breath.State public s;

    function observe(Breath.Config memory c, uint256 net) external { s.observe(c, net); }
    function payout(Breath.Config memory c, uint256 pot, uint256 yieldWk, uint256 rhoBps)
        external view returns (uint256 amount, Breath.Bind bind)
    { return s.payout(c, pot, yieldWk, rhoBps); }
    function commit(uint256 amount) external { s.commit(amount); }
    function validate(Breath.Config memory c) external pure { Breath.validate(c); }
}

/// @notice Hand-computed pins for the numbers and rules every other behaviour is derived from:
///         the breakeven anchor, the rise rail, the asymmetric fast average, and every
///         deploy-time bound in validate(), each by the error it should raise. Each was found
///         unpinned by a library-only test suite through mutation testing.
contract AnchorAndBounds is Test {
    BreathDirectHost h;

    function setUp() public { h = new BreathDirectHost(); }

    function _cfg() internal pure returns (Breath.Config memory) {
        return Breath.Config({
            slowAlphaBps:  385, fastDownBps: 5000, fastUpBps: 1820,
            floorBps:     2500, creepBps:      40,
            paceMinBps:   8500, paceMaxBps:  9500,
            trendLoBps:   9000, trendHiBps: 10200,
            riseBps:     12500, fallBps:     9400,
            coverTarget:   40, spareShareBps: 2500, minDraw: uint128(1_000_000)
        });
    }

    /// @dev PIN THE ANCHOR. Breakeven grosses income and yield UP by the recycled share,
    ///      because part of what is paid comes home: pay only income plus yield and the pot
    ///      keeps growing. At the rho used here (2,800) that gross-up is worth about 39%.
    ///      Every other number in the design is derived from this one, so it is computed by
    ///      hand here, and a change to the formula fails on the formula.
    function test_theBreakevenAnchorGrossesUpByTheRecycledShare() public {
        Breath.Config memory c = _cfg();
        uint256 income = 1_000_000e6;
        uint256 yieldWk = 20_000e6;
        uint256 rhoBps = 2_800;

        // One observation seeds both averages to the same figure, so trend is exactly parity
        // and pace interpolates at a known point in the band.
        h.observe(c, income);
        (uint256 amount, Breath.Bind bind) = h.payout(c, type(uint128).max, yieldWk, rhoBps);

        uint256 breakeven = ((income + yieldWk) * 10_000) / (10_000 - rhoBps);
        uint256 pace = uint256(c.paceMinBps)
            + ((uint256(c.paceMaxBps) - c.paceMinBps) * (10_000 - c.trendLoBps))
              / (uint256(c.trendHiBps) - c.trendLoBps);
        uint256 target = (breakeven * pace) / 10_000;
        uint256 floorAmt = ((income + yieldWk) * c.floorBps) / 10_000;

        // On a first draw the floor is what wants to be paid and breakeven is the ceiling,
        // so the amount is the floor and the gross-up is proved by the ceiling standing
        // above it. Assert both, so neither can drift unnoticed.
        assertEq(amount, floorAmt, "a first draw pays the income floor");
        assertEq(uint256(bind), uint256(Breath.Bind.FLOOR), "and says so");
        assertGt(target, ((income + yieldWk) * pace) / 10_000,
            "breakeven must gross up by the recycled share, not pay income plus yield flat");

        // Now drive it to the ceiling. lastPaid is set AT the target: creep then wants more
        // than breakeven allows so the cap binds, while the fall rail's floor (94% of
        // lastPaid) sits below it and does not push back. Set lastPaid much higher and the
        // fall rail wins instead, which is the documented ordering, not this test's subject.
        h.commit(target);
        (amount, bind) = h.payout(c, type(uint128).max, yieldWk, rhoBps);
        assertEq(amount, target, "when breakeven binds, it binds at the grossed-up figure");
    }

    /// @dev PIN EVERY DEPLOY BOUND. validate() is the function whose stated doctrine is that
    ///      a dangerous configuration must be impossible, and a mutation deleted its
    ///      recovery-inversion bound with all 142 tests still green. Table-driven so a new
    ///      bound gets a row rather than a new file.
    /// @dev PIN THE RISE RAIL. Income jumps a thousandfold after a small committed prize, so the
    ///      floor asks for far more than the last payment; the rail must hold the climb to
    ///      riseBps of the last payment and say so.
    function test_theRiseRailHoldsTheClimbToItsShare() public {
        Breath.Config memory c = _cfg();
        uint256 income = 1_000_000e6;
        uint256 last = 1_000e6;
        h.observe(c, income);
        h.commit(last);
        (uint256 amount, Breath.Bind bind) = h.payout(c, type(uint128).max, 0, 2_800);
        assertEq(amount, (last * c.riseBps) / 10_000, "held to the rise rail");
        assertEq(uint256(bind), uint256(Breath.Bind.RISE_RAIL), "and reports it");
    }

    /// @dev PIN THE ASYMMETRIC AVERAGE. The fast average follows a fall at fastDownBps and a
    ///      rise at fastUpBps, so the game reacts quickly to a decline and cautiously to a
    ///      recovery. Hand-computed both ways from the same starting point.
    function test_theFastAverageFallsQuicklyAndRisesSlowly() public {
        Breath.Config memory c = _cfg();
        uint256 start = 1_000_000e6;

        h.observe(c, start);
        h.observe(c, start / 2);
        (uint256 slowDown, uint256 fastDown,,) = h.s();
        assertEq(fastDown, start - ((start - start / 2) * c.fastDownBps) / 10_000, "fall at fastDownBps");
        assertEq(slowDown, start - ((start - start / 2) * c.slowAlphaBps) / 10_000, "slow at slowAlphaBps");

        BreathDirectHost up = new BreathDirectHost();
        up.observe(c, start);
        up.observe(c, start * 2);
        (, uint256 fastUp,,) = up.s();
        assertEq(fastUp, start + ((start * 2 - start) * c.fastUpBps) / 10_000, "rise at fastUpBps");
    }

    function test_everyDeployBoundRejects() public {
        Breath.Config memory c;

        c = _cfg(); c.slowAlphaBps = 2_000;                 // slow faster than fast up
        vm.expectRevert(Breath.BadAlpha.selector); h.validate(c);

        c = _cfg(); c.fastUpBps = 6_000;                    // fast up slower than fast down
        vm.expectRevert(Breath.BadAlpha.selector); h.validate(c);

        c = _cfg(); c.fastDownBps = 10_001;                 // an average faster than instant
        vm.expectRevert(Breath.BadAlpha.selector); h.validate(c);

        c = _cfg(); c.paceMinBps = 9_600;                   // min above max
        vm.expectRevert(Breath.BadPace.selector); h.validate(c);

        c = _cfg(); c.paceMaxBps = 10_001;                  // pace above breakeven
        vm.expectRevert(Breath.BadPace.selector); h.validate(c);

        c = _cfg(); c.trendLoBps = 10_300;                  // band ordered but above parity
        vm.expectRevert(Breath.BadTrend.selector); h.validate(c);

        c = _cfg(); c.trendHiBps = 9_500; c.trendLoBps = 9_000;  // band entirely below parity
        vm.expectRevert(Breath.BadTrend.selector); h.validate(c);

        c = _cfg(); c.floorBps = 4_500;                     // opening prize too near breakeven
        vm.expectRevert(Breath.BadShare.selector); h.validate(c);

        c = _cfg(); c.floorBps = 0;
        vm.expectRevert(Breath.BadShare.selector); h.validate(c);

        c = _cfg(); c.creepBps = 1_001;
        vm.expectRevert(Breath.BadShare.selector); h.validate(c);

        c = _cfg(); c.riseBps = 10_000;                     // a rise rail that cannot rise
        vm.expectRevert(Breath.BadRails.selector); h.validate(c);

        c = _cfg(); c.fallBps = 10_000;                     // a fall rail that cannot fall
        vm.expectRevert(Breath.BadRails.selector); h.validate(c);

        c = _cfg(); c.fallBps = 0;
        vm.expectRevert(Breath.BadRails.selector); h.validate(c);

        // minDraw = 0 is legal: it switches the dust guard off, which a host may want because
        // the guard defends running costs rather than solvency. Asserted as accepted, so the
        // permission is pinned as deliberately as the refusals around it.
        c = _cfg(); c.minDraw = 0;
        h.validate(c);

        c = _cfg(); c.minDraw = uint128(10_001e6);          // a guard wider than real games
        vm.expectRevert(Breath.BadShare.selector); h.validate(c);

        c = _cfg(); c.coverTarget = 0;
        vm.expectRevert(Breath.BadCover.selector); h.validate(c);

        c = _cfg(); c.spareShareBps = 10_000;               // a call that takes the whole band
        vm.expectRevert(Breath.BadCover.selector); h.validate(c);

        c = _cfg(); c.spareShareBps = 0;
        vm.expectRevert(Breath.BadCover.selector); h.validate(c);

        h.validate(_cfg());                                 // and the shipped dials pass
    }
}

/// @notice The seed's door. With the return-to-pot deleted, the money orphans in the
///         contract's balance, the next yield capture relabels it as interest, the pot ends
///         up whole and all 142 tests pass. The self-healing capture is a safety net for
///         money and a blindfold for tests: any leak on the pot side is laundered into
///         "yield" before an assertion can see it.
