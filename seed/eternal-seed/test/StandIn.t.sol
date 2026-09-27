// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StandInGame} from "./StandInGame.sol";

/// @notice What the seed rule does to a pot over many draws, run through the stand-in game.
/// @dev    One flat income stream, the same in every game, so the only difference between
///         games is how much of the pot each keeps back. Yield is 10 bps per draw on the
///         balance held, about 5.3% a year at 52 draws. Figures are in a six-decimal token.
///         Three games are compared:
///           SEEDED    FLOW, a pool of 5% of the pot each draw, 10% of it seeded back.
///           UNSEEDED  FLOW, the same pool, nothing seeded back.
///           NO POT    pays out everything it holds each draw, so it holds nothing and earns
///                     no yield: the prize is the draw's income.
contract StandInTest is Test {
    uint256 internal constant INCOME = 10_000e6;
    uint256 internal constant YIELD_BPS = 10;
    uint256 internal constant YEARS = 10;
    uint256 internal constant DRAWS = 52 * YEARS;

    function _seeded() internal returns (StandInGame) {
        return new StandInGame(StandInGame.Retention.FLOW, 500, 1_000, 0, YIELD_BPS);
    }

    function _unseeded() internal returns (StandInGame) {
        return new StandInGame(StandInGame.Retention.FLOW, 500, 0, 0, YIELD_BPS);
    }

    function _noPot() internal returns (StandInGame) {
        return new StandInGame(StandInGame.Retention.FLOW, 10_000, 0, 0, YIELD_BPS);
    }

    function _run(StandInGame g, uint256 draws, uint256 income) internal {
        for (uint256 i = 0; i < draws; i++) g.draw(income);
    }

    /// @notice Every unit that came in, as income or yield, was either paid or is still in the
    ///         pot, in both retention rules, at any income.
    function testFuzz_everyUnitIsAccountedFor(uint256 seedIncome, bool floor) public {
        StandInGame g = floor
            ? new StandInGame(StandInGame.Retention.FLOOR, 450, 0, 1_000, YIELD_BPS)
            : _seeded();
        for (uint256 i = 0; i < 60; i++) {
            uint256 income = uint256(keccak256(abi.encode(seedIncome, i))) % (INCOME * 10);
            g.draw(income);
            assertEq(g.totalIncome() + g.totalYield(), g.totalPaid() + g.pot(), "in equals out plus held");
        }
    }

    /// @notice A HELD POT PAYS MORE THAN ITS INCOME. Once the pot has built, each draw pays the
    ///         draw's income plus the yield the pot earned. A game that holds nothing pays the
    ///         income and no more.
    function test_aHeldPotPaysMoreThanItsIncome() public {
        StandInGame seeded = _seeded();
        StandInGame noPot = _noPot();
        uint256 crossedAt;
        for (uint256 i = 1; i <= DRAWS; i++) {
            seeded.draw(INCOME);
            noPot.draw(INCOME);
            if (crossedAt == 0 && seeded.lastPaid() > INCOME) crossedAt = i;
        }
        emit log_named_uint("seeded prize first beats income at draw", crossedAt);
        emit log_named_decimal_uint("seeded prize after 10 years", seeded.lastPaid(), 6);
        emit log_named_decimal_uint("no-pot prize after 10 years", noPot.lastPaid(), 6);
        emit log_named_decimal_uint("seeded pot, in draws of income", (seeded.pot() * 1e6) / INCOME, 6);

        assertEq(noPot.lastPaid(), INCOME, "a game holding nothing pays its income");
        assertEq(noPot.totalYield(), 0, "and earns nothing");
        assertGt(crossedAt, 0, "the held pot's prize passes income");
        assertGt(seeded.lastPaid(), INCOME, "and stays above it");
    }

    /// @notice THE SEED MAKES THE POT BIGGER, AT A PRICE PAID EARLY. Keeping 10% of each pool
    ///         back pays less in the first year and builds a bigger pot, which earns more yield,
    ///         so by the tenth year each draw pays more than the unseeded game's.
    function test_theSeedMakesThePotBigger() public {
        StandInGame seeded = _seeded();
        StandInGame unseeded = _unseeded();

        _run(seeded, 52, INCOME);
        _run(unseeded, 52, INCOME);
        emit log_named_decimal_uint("year one paid, seeded  ", seeded.totalPaid(), 6);
        emit log_named_decimal_uint("year one paid, unseeded", unseeded.totalPaid(), 6);
        assertLt(seeded.totalPaid(), unseeded.totalPaid(), "the seed pays less in year one");

        _run(seeded, DRAWS - 52, INCOME);
        _run(unseeded, DRAWS - 52, INCOME);
        emit log_named_decimal_uint("pot after 10 years, seeded  ", seeded.pot(), 6);
        emit log_named_decimal_uint("pot after 10 years, unseeded", unseeded.pot(), 6);
        emit log_named_decimal_uint("prize after 10 years, seeded  ", seeded.lastPaid(), 6);
        emit log_named_decimal_uint("prize after 10 years, unseeded", unseeded.lastPaid(), 6);
        assertGt(seeded.pot(), unseeded.pot(), "the seeded pot is bigger");
        assertGt(seeded.lastPaid(), unseeded.lastPaid(), "and its draw pays more");
    }

    /// @notice THE SEED KEEPS PAYING WHEN INCOME STOPS. After ten years, income stops for a
    ///         year. The game with no pot pays nothing. Both held pots keep paying every draw,
    ///         and the seeded pot, being bigger, pays more across the dry year.
    function test_theSeedKeepsPayingAfterIncomeStops() public {
        StandInGame seeded = _seeded();
        StandInGame unseeded = _unseeded();
        StandInGame noPot = _noPot();
        _run(seeded, DRAWS, INCOME);
        _run(unseeded, DRAWS, INCOME);
        _run(noPot, DRAWS, INCOME);

        uint256 paidBeforeS = seeded.totalPaid();
        uint256 paidBeforeU = unseeded.totalPaid();
        uint256 paidBeforeN = noPot.totalPaid();
        for (uint256 i = 0; i < 52; i++) {
            assertGt(seeded.draw(0), 0, "the seeded game pays every dry draw");
            assertGt(unseeded.draw(0), 0, "so does the unseeded one");
            noPot.draw(0);
        }
        uint256 dryS = seeded.totalPaid() - paidBeforeS;
        uint256 dryU = unseeded.totalPaid() - paidBeforeU;
        uint256 dryN = noPot.totalPaid() - paidBeforeN;
        emit log_named_decimal_uint("dry year paid, seeded, in draws of old income  ", (dryS * 1e6) / INCOME, 6);
        emit log_named_decimal_uint("dry year paid, unseeded, in draws of old income", (dryU * 1e6) / INCOME, 6);

        assertEq(dryN, 0, "no pot, nothing to pay");
        assertGt(dryS, dryU, "the bigger pot carries the dry year further");
    }

    /// @notice FLOOR AND FLOW GROW ALIKE AT THE SAME EFFECTIVE RATE. Paying 4.5% of the pot
    ///         under Floor and paying 90% of a 5% pool under Flow take the same share, so the
    ///         two pots track each other to within rounding. What differs is the promise: Floor
    ///         keeps a fixed share of the pot out of reach whatever the rate, Flow returns a
    ///         fixed share of every pool. The Floor game checks its floor on every draw.
    function test_floorAndFlowGrowAlikeAtTheSameEffectiveRate() public {
        StandInGame flow = _seeded();
        StandInGame floor_ = new StandInGame(StandInGame.Retention.FLOOR, 450, 0, 1_000, YIELD_BPS);
        _run(flow, DRAWS, INCOME);
        _run(floor_, DRAWS, INCOME);
        uint256 gap = flow.pot() > floor_.pot() ? flow.pot() - floor_.pot() : floor_.pot() - flow.pot();
        emit log_named_decimal_uint("pot, flow ", flow.pot(), 6);
        emit log_named_decimal_uint("pot, floor", floor_.pot(), 6);
        emit log_named_uint("gap in the smallest unit", gap);
        assertLe(gap * 1e9, flow.pot(), "within a billionth of each other");
    }

    /// @notice A Floor game run at its ceiling rate every draw still leaves the invariant floor
    ///         in the pot; the game reverts if it does not.
    function test_floorHoldsAtTheCeilingRate() public {
        StandInGame g = new StandInGame(StandInGame.Retention.FLOOR, 1_000, 0, 1_000, YIELD_BPS);
        _run(g, DRAWS, INCOME);
        assertGt(g.pot(), 0, "a floor is still there");
    }
}
