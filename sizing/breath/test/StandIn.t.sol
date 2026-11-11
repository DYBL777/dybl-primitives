// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Breath} from "../src/Breath.sol";
import {StandInGame} from "./StandInGame.sol";

/// @notice Breath run by the stand-in game: no tickets, no randomness, just the library over
///         many draws, so its long-run behaviour can be checked on its own.
contract StandInTest is Test {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant USDC = 1e6;
    uint256 internal constant INCOME = 4_000_000 * USDC; // 1M tickets at $5, 20% to treasury
    // The recycled share at the shipped split and a ~83% jackpot miss rate (see Base.t.sol).
    uint256 internal constant RHO = 2_000 + (3_300 * 3_000 * 8_300) / (BPS * BPS);
    // Weekly yield on the pot as it stands: 3.4% a year compounded weekly is about 6.43 bps.
    uint256 internal constant YIELD_PPM = 643;

    function cfg() internal pure returns (Breath.Config memory) {
        return Breath.Config({
            slowAlphaBps: 385, fastDownBps: 5000, fastUpBps: 1820,
            floorBps: 2500, creepBps: 40,
            paceMinBps: 8500, paceMaxBps: 9500,
            trendLoBps: 9000, trendHiBps: 10200,
            riseBps: 12500, fallBps: 9400,
            coverTarget: 40, spareShareBps: 2500, minDraw: uint128(0)
        });
    }

    function _yield(StandInGame g) internal view returns (uint256) {
        return (g.pot() * YIELD_PPM) / 1_000_000;
    }

    /// @dev On a flat book with no yield, the first payout is the floor, every payout stays at
    ///      or under the pace-scaled breakeven, and so the pot grows every draw.
    function test_flatIncomeStartsAtTheFloorAndStaysUnderBreakeven() public {
        StandInGame g = new StandInGame(cfg(), RHO, 0, 0);
        uint256 breakeven = (INCOME * BPS) / (BPS - RHO);
        // trend is parity on a flat book: pace sits 1,000/1,200 of the way up the band
        uint256 band = 1000;
        uint256 pace = 8500 + (band * 1000) / 1200;
        uint256 target = (breakeven * pace) / BPS;

        (uint256 first, Breath.Bind bind,) = g.draw(INCOME, 0);
        assertEq(first, INCOME * 2500 / BPS, "opens at the floor");
        assertEq(uint256(bind), uint256(Breath.Bind.FLOOR));

        // Creep then adds 0.4% of the slow average a draw ($16,000 here) until breakeven caps it.
        uint256 step = (INCOME * 40) / BPS;
        uint256 prevPot = g.pot();
        uint256 prevPaid = first;
        uint256 capturedAt;
        for (uint256 i; i < 299; i++) {
            (uint256 a, Breath.Bind b,) = g.draw(INCOME, 0);
            assertLe(a, target, "over the pace-scaled breakeven");
            assertGt(g.pot(), prevPot, "pot shrank on a flat book");
            if (b == Breath.Bind.CREEP) assertEq(a, prevPaid + step, "creep step");
            if (b == Breath.Bind.BREAKEVEN && capturedAt == 0) capturedAt = i + 2;
            prevPot = g.pot();
            prevPaid = a;
        }
        emit log_named_uint("draw where breakeven took over", capturedAt);
        assertGt(capturedAt, 0, "breakeven took over from creep");
        assertEq(g.lastPaid(), target, "holds at the target");
    }

    /// @dev Over any income stream, each payout moves at most one rail from the last, unless the
    ///      pot itself is the limit, and no draw overpays the pot (the stand-in reverts if one does).
    function testFuzz_payoutsStayInsideTheRails(uint256 seed) public {
        StandInGame g = new StandInGame(cfg(), RHO, 4, BPS);
        uint256 last;
        for (uint256 i; i < 120; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 income = bound(seed, 0, 3 * INCOME);
            (uint256 a, Breath.Bind bind,) = g.draw(income, _yield(g));
            if (last != 0 && bind != Breath.Bind.POT && bind != Breath.Bind.DUST) {
                assertGe(a, (last * 9400) / BPS, "fell more than the fall rail");
                assertLe(a, (last * 12500) / BPS, "rose more than the rise rail");
            }
            last = a;
        }
    }

    /// @dev A 99% income collapse after a year: the payout glides down, no more than 6% a draw,
    ///      and the reserve built in the good year carries it.
    function test_collapseGlidesDownOnTheFallRail() public {
        StandInGame g = new StandInGame(cfg(), RHO, 0, 0);
        for (uint256 i; i < 52; i++) g.draw(INCOME, _yield(g));
        uint256 last = g.lastPaid();
        for (uint256 i; i < 26; i++) {
            (uint256 a, Breath.Bind bind,) = g.draw(INCOME / 100, _yield(g));
            if (bind != Breath.Bind.POT) assertGe(a, (last * 9400) / BPS, "dropped harder than the rail");
            last = a;
        }
        assertGt(g.pot(), 0, "the reserve is still there after six months of collapse");
    }

    /// @dev The library's own warning, shown: on a flat book with yield, a pot nothing spends
    ///      keeps growing. With `spare()` offered every four draws the pot levels off.
    function test_spareKeepsAFlatBooksPotFromGrowingForever() public {
        StandInGame hoard = new StandInGame(cfg(), RHO, 0, 0);
        StandInGame spend = new StandInGame(cfg(), RHO, 4, BPS);

        uint256 hoardAt10;
        uint256 spendAt10;
        for (uint256 i; i < 1040; i++) {
            hoard.draw(INCOME, _yield(hoard));
            spend.draw(INCOME, _yield(spend));
            if (i == 519) {
                hoardAt10 = hoard.pot();
                spendAt10 = spend.pot();
            }
        }
        emit log_named_uint("hoard pot, year 10 ($M)", hoardAt10 / 1e12);
        emit log_named_uint("hoard pot, year 20 ($M)", hoard.pot() / 1e12);
        emit log_named_uint("spend pot, year 10 ($M)", spendAt10 / 1e12);
        emit log_named_uint("spend pot, year 20 ($M)", spend.pot() / 1e12);
        emit log_named_uint("spend cover, year 20 (draws of payout)", spend.pot() / spend.lastPaid());

        assertGt(hoard.pot(), (hoardAt10 * 12) / 10, "the hoard kept growing in the second decade");
        assertLt(spend.pot(), (spendAt10 * 105) / 100, "the spender levelled off");
        assertLt(spend.pot(), hoard.pot(), "spending held the pot below the hoard");
    }

    /// @dev Income stops after two years. The payout glides down until the dust guard refuses a
    ///      draw; that draw is not recorded, so when income returns the next payout steps from
    ///      the last real prize, inside the rise rail, rather than starting again from nothing.
    function test_aRefusedDrawIsNotTheNextDrawsStartingPoint() public {
        Breath.Config memory c = cfg();
        c.minDraw = uint128(1_000 * USDC);
        StandInGame g = new StandInGame(c, RHO, 0, 0);
        for (uint256 i; i < 104; i++) g.draw(INCOME, 0);
        Breath.Bind bind;
        uint256 refusedAt;
        for (uint256 i; i < 520; i++) {
            (, bind,) = g.draw(0, 0);
            if (bind == Breath.Bind.DUST) { refusedAt = i + 1; break; }
        }
        assertGt(refusedAt, 0, "precondition: a draw was refused as dust");
        uint256 last = g.lastPaid();
        assertGt(last, 0, "the refused draw left the last real prize in place");
        (uint256 a,,) = g.draw(INCOME, 0);
        assertLe(a, (last * 12500) / BPS, "the first draw back rose past the rise rail");
        emit log_named_uint("draws of no income before the guard refused one", refusedAt);
    }

    function test_dustGuardRefusesASmallPayout() public {
        Breath.Config memory c = cfg();
        c.minDraw = uint128(1_000 * USDC);
        StandInGame g = new StandInGame(c, RHO, 0, 0);
        (uint256 a, Breath.Bind bind,) = g.draw(100 * USDC, 0); // floor would be $25
        assertEq(a, 0);
        assertEq(uint256(bind), uint256(Breath.Bind.DUST));
    }

    function test_noIncomeNoPayout() public {
        StandInGame g = new StandInGame(cfg(), RHO, 0, 0);
        (uint256 a, Breath.Bind bind,) = g.draw(0, 0);
        assertEq(a, 0);
        assertEq(uint256(bind), uint256(Breath.Bind.DUST));
    }

    function test_constructorRefusesBadSettings() public {
        vm.expectRevert(StandInGame.BadReturn.selector);
        new StandInGame(cfg(), BPS, 0, 0);

        vm.expectRevert(StandInGame.BadSpare.selector);
        new StandInGame(cfg(), RHO, 4, 0);

        Breath.Config memory c = cfg();
        c.floorBps = 0;
        vm.expectRevert(Breath.BadShare.selector);
        new StandInGame(c, RHO, 0, 0);
    }
}
