// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

/// @notice THE OPENING SHARE ACROSS ITS WHOLE RANGE, and what a shrinking crowd does to it.
///         The other suites hold the opening between 10% and 50%; the library accepts 0% to
///         100%, so these run every part of that range through whole seasons.
///
///         The game modelled: 1,000 players at the start on a $5 ticket, 80% of it into the
///         pot ($4,000 a week), 4% a year of yield compounding weekly on the pot as it grows,
///         and 29.9% of every payment but the last coming back to the pot. The crowd is the
///         variable: steady, shrinking at a set rate, leaving all at once, or at random.
///
///         Two measures. The DRAW'S PRIZE is what a draw pays in all. The PRIZE PER TICKET is
///         that divided by the tickets in the draw, which is what each player's chance is
///         worth: when players leave, the prize can fall while each remaining ticket's share
///         of it rises.
///
///         The fuzz tests run at the suite's setting of 256 runs. The figures quoted elsewhere
///         for 10,000 runs come from `FOUNDRY_FUZZ_RUNS=10000 forge test --match-contract Opening`.
contract Opening is Test {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant RET = 2_990;
    uint256 internal constant WEEK = 4_000e6;  // 1,000 players x $5 x 80%

    // Figures pinned for the runs made the way Lettery TF passes the last payment.
    uint256 internal constant TF_SHRINK_D26 = 3_384_560_783;
    uint256 internal constant TF_SHRINK_CLOSE = 4_066_064_601;
    uint256 internal constant TF_GROW_1 = 9_300;  // 1% more players a draw
    uint256 internal constant TF_GROW_2 = 2_600;  // 2%
    uint256 internal constant TF_GROW_3 = 600;    // 3%

    /// A season on `inc` (each draw's income, which is also the forecast the library is
    /// given). `seed` is money already in the pot before draw 1. `capTenths`, when not zero,
    /// is a host-side cap on the opening of capTenths/10 weeks of this draw's income, worked
    /// out before the library is asked; the library is unchanged.
    function _season(uint256[] memory inc, uint256 openingBps, uint256 seed, uint256 capTenths)
        internal
        returns (uint256[] memory paid, SeasonArc.Bind[] memory binds)
    {
        return _run(inc, openingBps, seed, capTenths, false);
    }

    /// The same season run the way Lettery TF runs it: the last payment handed to the library
    /// is scaled by how the crowd changed since that draw (`LetteryTF.sol`, "THE ANCHOR,
    /// CARRIED PER TICKET"), so the library grows the value of a win rather than the size of a
    /// draw. Income stands for the crowd, as everywhere in this file.
    function _seasonTf(uint256[] memory inc, uint256 openingBps)
        internal
        returns (uint256[] memory paid, SeasonArc.Bind[] memory binds)
    {
        return _run(inc, openingBps, 0, 0, true);
    }

    function _run(uint256[] memory inc, uint256 openingBps, uint256 seed, uint256 capTenths, bool perTicketAnchor)
        internal
        returns (uint256[] memory paid, SeasonArc.Bind[] memory binds)
    {
        uint256 n = inc.length;
        paid = new uint256[](n);
        binds = new SeasonArc.Bind[](n);
        uint256 pot = seed;
        uint256 last;
        for (uint256 d; d < n; d++) {
            pot += inc[d] + (pot * 400) / (52 * BPS);
            uint256 op = openingBps;
            if (last == 0 && capTenths != 0 && pot != 0) {
                uint256 capped = (inc[d] * capTenths * 1_000) / pot;
                if (capped < op) op = capped;
            }
            uint256 anchor = last;
            if (perTicketAnchor && anchor != 0 && d != 0) anchor = (anchor * inc[d]) / inc[d - 1];
            (uint256 a, SeasonArc.Bind b) = SeasonArc.size(pot, anchor, n - d, inc[d], RET, op);
            assertLe(a, pot, "a draw paid more than the pot held");
            paid[d] = a;
            binds[d] = b;
            pot -= a;
            if (d + 1 < n) pot += (a * RET) / BPS;
            last = a;
        }
        assertEq(pot, 0, "the closing draw took what was left");
    }

    /// Draws that paid less in all than the one before.
    function _falls(uint256[] memory paid) internal pure returns (uint256 f) {
        for (uint256 i = 1; i < paid.length; i++) if (paid[i] < paid[i - 1]) f++;
    }

    /// Draws whose prize per ticket was below the one before (income stands for tickets).
    function _ticketFalls(uint256[] memory paid, uint256[] memory inc) internal pure returns (uint256 f) {
        for (uint256 i = 1; i < paid.length; i++) if (paid[i] * inc[i - 1] < paid[i - 1] * inc[i]) f++;
    }

    /// A crowd leaving at `tenthsOfPct`/10 % a draw, compounding.
    function _shrinking(uint256 n, uint256 tenthsOfPct) internal pure returns (uint256[] memory inc) {
        inc = new uint256[](n);
        uint256 c = 1e18;
        for (uint256 d; d < n; d++) {
            inc[d] = (WEEK * c) / 1e18;
            c = (c * (1_000 - tenthsOfPct)) / 1_000;
        }
    }

    /// A crowd that only leaves or stays: each draw, a 5% chance that between 1% and 90% of it
    /// leaves at once, a 55% chance that up to 8% leaves, otherwise steady.
    function _leaving(uint256 rand, uint256 n) internal pure returns (uint256[] memory inc) {
        inc = new uint256[](n);
        uint256 c = WEEK;
        for (uint256 d; d < n; d++) {
            inc[d] = c;
            uint256 r = uint256(keccak256(abi.encode(rand, d)));
            if (r % 100 < 5) c = (c * (10 + ((r >> 8) % 90))) / 100;
            else if (r % 100 < 60) c = (c * (920 + ((r >> 8) % 81))) / 1_000;
            if (c < 1e6) c = 1e6;
        }
    }

    /// A crowd growing at `tenthsOfPct`/10 % a draw, compounding.
    function _growing(uint256 n, uint256 tenthsOfPct) internal pure returns (uint256[] memory inc) {
        inc = new uint256[](n);
        uint256 c = 1e18;
        for (uint256 d; d < n; d++) {
            inc[d] = (WEEK * c) / 1e18;
            c = (c * (1_000 + tenthsOfPct)) / 1_000;
        }
    }

    /// A full crowd until draw `k`, then `dropPct`% of it gone for good.
    function _exodus(uint256 n, uint256 k, uint256 dropPct) internal pure returns (uint256[] memory inc) {
        inc = new uint256[](n);
        for (uint256 d; d < n; d++) inc[d] = d + 1 < k ? WEEK : (WEEK * (100 - dropPct)) / 100;
    }

    // ---------------------------------------------------------------- a steady crowd

    /// @dev A steady crowd climbs at every opening from 0.01% to 100%: no draw pays less than
    ///      the one before. A higher opening pays more on draw 1 and climbs less.
    function test_aSteadyCrowdClimbsAtEveryOpening() public {
        uint256[] memory inc = _shrinking(52, 0);
        uint256[7] memory open = [uint256(1), 500, 1_000, 2_500, 5_000, 7_500, 10_000];
        uint256[7] memory first = [uint256(400_000), 200e6, 400e6, 1_000e6, 2_000e6, 3_000e6, 4_000e6];
        uint256[7] memory close = [
            uint256(57_938_866_633), 26_898_770_245, 22_668_138_193, 16_808_742_943,
            12_247_469_262, 9_595_894_110, 7_772_202_676
        ];
        for (uint256 i; i < 7; i++) {
            (uint256[] memory paid, SeasonArc.Bind[] memory binds) = _season(inc, open[i], 0, 0);
            assertEq(_falls(paid), 0, "a steady crowd had a draw pay less than the one before");
            assertEq(uint256(binds[0]), uint256(SeasonArc.Bind.OPENING));
            assertGt(paid[1], paid[0], "draw 2 is above draw 1");
            assertEq(paid[0], first[i], "draw 1");
            assertEq(paid[51], close[i], "the closing draw");
            emit log_named_uint("opening (bps)", open[i]);
            emit log_named_uint("  closing draw over draw 1 (x100)", (paid[51] * 100) / paid[0]);
        }
    }

    // ---------------------------------------------------------------- a shrinking crowd

    /// @dev The highest opening, to the nearest 1%, at which a crowd leaving at a steady rate
    ///      never makes a draw pay less than the one before, over 52 draws. The figure is pinned
    ///      from both sides: no fall at it, a fall 1% above it.
    function test_theHighestOpeningASteadyShrinkAllows() public {
        uint256[6] memory rate = [uint256(5), 10, 15, 20, 30, 50];  // tenths of a percent a draw
        uint256[6] memory most = [uint256(7_900), 5_200, 3_700, 2_800, 1_800, 1_100];
        for (uint256 i; i < 6; i++) {
            uint256[] memory inc = _shrinking(52, rate[i]);
            (uint256[] memory at,) = _season(inc, most[i], 0, 0);
            (uint256[] memory above,) = _season(inc, most[i] + 100, 0, 0);
            assertEq(_falls(at), 0, "a fall at the opening the shrink allows");
            assertGt(_falls(above), 0, "no fall 1% above it: the pinned figure is too low");
        }
    }

    /// @dev The same at a 2% shrink for other season lengths: a short season takes a much
    ///      higher opening, a long one a much lower.
    function test_aLongerSeasonNeedsALowerOpening() public {
        uint256[4] memory n = [uint256(12), 26, 104, 156];
        uint256[4] memory most = [uint256(9_600), 5_800, 1_300, 1_000];
        for (uint256 i; i < 4; i++) {
            uint256[] memory inc = _shrinking(n[i], 20);
            (uint256[] memory at,) = _season(inc, most[i], 0, 0);
            (uint256[] memory above,) = _season(inc, most[i] + 100, 0, 0);
            assertEq(_falls(at), 0, "a fall at the opening the season length allows");
            assertGt(_falls(above), 0, "no fall 1% above it");
        }
    }

    /// @dev Part of the crowd leaves at once and does not come back. The later it happens and
    ///      the more leave, the lower the opening that carries it without a fall.
    function test_theHighestOpeningASuddenExodusAllows() public {
        // [draw it happens, share that leaves, highest opening]
        uint256[3][6] memory c = [
            [uint256(13), 50, 6_700], [uint256(26), 50, 5_900], [uint256(51), 50, 1_200],
            [uint256(13), 90, 2_500], [uint256(26), 90, 2_600], [uint256(51), 90, 300]
        ];
        for (uint256 i; i < 6; i++) {
            uint256[] memory inc = _exodus(52, c[i][0], c[i][1]);
            (uint256[] memory at,) = _season(inc, c[i][2], 0, 0);
            (uint256[] memory above,) = _season(inc, c[i][2] + 100, 0, 0);
            assertEq(_falls(at), 0, "a fall at the opening the exodus allows");
            assertGt(_falls(above), 0, "no fall 1% above it");
        }
    }

    /// @dev Where the draw's prize does fall, the fallback keeps it a step, not a slide: at a
    ///      quarter opening and a crowd leaving 5% a draw, no draw pays 2% less than the one
    ///      before it.
    function test_whereThePrizeFallsItSteps() public {
        (uint256[] memory paid,) = _season(_shrinking(52, 50), 2_500, 0, 0);
        assertGt(_falls(paid), 0, "precondition: this shrink makes the prize fall");
        for (uint256 i = 1; i < 52; i++) {
            assertGe(paid[i] * 100, paid[i - 1] * 98, "a draw fell 2% or more below the one before");
        }
    }

    // ---------------------------------------------------------------- the prize per ticket

    /// @dev Players leave and none join. Whatever the opening, the season's length and how the
    ///      crowd leaves (a little, a lot, or most of it at once), no draw's prize per ticket is
    ///      below the one before: the prize may fall, but it is shared by fewer.
    function testFuzz_playersLeavingNeverLowerThePrizePerTicket(uint256 rand, uint256 n, uint256 openingBps)
        public
    {
        n = bound(n, 2, 104);
        openingBps = bound(openingBps, 1, BPS);
        uint256[] memory inc = _leaving(rand, n);
        (uint256[] memory paid,) = _season(inc, openingBps, 0, 0);
        assertEq(_ticketFalls(paid, inc), 0, "players left and the prize per ticket fell");
    }

    /// @dev The same grid of sudden exits as above, at openings from 1% to 100%: the prize
    ///      per ticket never falls in any of them.
    function test_aSuddenExodusNeverLowersThePrizePerTicket() public {
        uint256[3] memory k = [uint256(2), 26, 51];
        uint256[3] memory drop = [uint256(30), 70, 90];
        for (uint256 i; i < 3; i++) {
            for (uint256 j; j < 3; j++) {
                uint256[] memory inc = _exodus(52, k[i], drop[j]);
                for (uint256 o = 100; o <= BPS; o += 1_100) {
                    (uint256[] memory paid,) = _season(inc, o, 0, 0);
                    assertEq(_ticketFalls(paid, inc), 0, "an exodus lowered the prize per ticket");
                }
            }
        }
    }

    // ---------------------------------------------------------------- a carried seed

    /// @dev Money already in the pot before draw 1 (five weeks' income here). At a 100%
    ///      opening, draw 1 spends it and draw 2 is cut to a quarter of it, so the prize per
    ///      ticket falls with no player leaving. At a quarter opening it does not fall.
    function test_aCarriedSeedAtAHighOpeningCutsDrawTwo() public {
        uint256[] memory inc = _shrinking(52, 0);
        (uint256[] memory paid, SeasonArc.Bind[] memory binds) = _season(inc, BPS, 20_000e6, 0);
        assertEq(paid[0], 24_015_384_615, "draw 1 pays the seed and the week's income");
        assertEq(paid[1], 5_858_144_895, "draw 2");
        assertEq(uint256(binds[1]), uint256(SeasonArc.Bind.SUSTAINED), "the arc cannot hold draw 1, so it falls back");
        assertEq(_ticketFalls(paid, inc), 1, "one fall, at draw 2");
        (uint256[] memory quarter,) = _season(inc, 2_500, 20_000e6, 0);
        assertEq(_ticketFalls(quarter, inc), 0, "a quarter opening carries the same seed");
    }

    /// @dev The host caps the opening at one week's income before asking the library. With
    ///      the cap, the same seed is paid out through the climb instead of on draw 1.
    function test_anIncomeCapPaysTheSeedThroughTheClimb() public {
        uint256[] memory inc = _shrinking(52, 0);
        (uint256[] memory paid,) = _season(inc, BPS, 20_000e6, 10);
        assertEq(paid[0], 3_998_561_538, "draw 1 is about a week's income");
        assertEq(_falls(paid), 0, "and the season climbs from there");
        assertEq(paid[51], 9_198_031_789, "the closing draw");
    }

    /// @dev With that cap, a seed of up to ten weeks' income, any opening and a crowd that
    ///      only leaves: the prize per ticket never falls.
    function testFuzz_aCappedOpeningCarriesASeedWithoutAFall(
        uint256 rand,
        uint256 n,
        uint256 openingBps,
        uint256 seedWeeks
    ) public {
        n = bound(n, 2, 104);
        openingBps = bound(openingBps, 1, BPS);
        uint256 seed = bound(seedWeeks, 0, 100) * WEEK / 10;
        uint256[] memory inc = _leaving(rand, n);
        (uint256[] memory paid,) = _season(inc, openingBps, seed, 10);
        assertEq(_ticketFalls(paid, inc), 0, "a capped opening let a seed lower the prize per ticket");
    }

    // ---------------------------------------------------------------- the anchor Lettery TF passes

    /// @dev The same crowd rule, run the way Lettery TF runs it (the last payment scaled by the
    ///      crowd): players leaving does not lower the prize per ticket, at any opening.
    function testFuzz_tfAnchorPlayersLeavingNeverLowerThePrizePerTicket(uint256 rand, uint256 n, uint256 openingBps)
        public
    {
        n = bound(n, 2, 104);
        openingBps = bound(openingBps, 1, BPS);
        uint256[] memory inc = _leaving(rand, n);
        (uint256[] memory paid,) = _seasonTf(inc, openingBps);
        assertEq(_ticketFalls(paid, inc), 0, "players left and the prize per ticket fell");
    }

    /// @dev A crowd leaving 2% a draw at a 100% opening, run TF's way. The draw's prize follows
    ///      the crowd down on 36 draws, as the scaled anchor intends; the prize per ticket does
    ///      not fall and no draw falls back to SUSTAINED.
    function test_tfAnchorAShrinkingCrowdHoldsThePrizePerTicket() public {
        uint256[] memory inc = _shrinking(52, 20);
        (uint256[] memory paid, SeasonArc.Bind[] memory binds) = _seasonTf(inc, BPS);
        for (uint256 i; i < 52; i++) assertTrue(binds[i] != SeasonArc.Bind.SUSTAINED, "a draw fell back");
        assertEq(_ticketFalls(paid, inc), 0, "the prize per ticket fell");
        assertEq(_falls(paid), 35, "the draw's prize follows the crowd down");
        assertEq(paid[0], 4_000e6, "draw 1");
        assertEq(paid[25], TF_SHRINK_D26, "draw 26");
        assertEq(paid[51], TF_SHRINK_CLOSE, "the closing draw");
    }

    /// @dev Run TF's way, the highest opening at which a crowd leaving at a steady rate never
    ///      makes a draw pay less than the one before, pinned from both sides. Far higher than
    ///      the same crowds allow when the last payment is passed as it was.
    function test_tfAnchorTheHighestOpeningASteadyShrinkAllows() public {
        // [draws, tenths of a percent leaving each draw, highest opening]
        uint256[3][3] memory c = [[uint256(52), 20, 8_000], [uint256(52), 50, 2_800], [uint256(104), 20, 4_100]];
        for (uint256 i; i < 3; i++) {
            uint256[] memory inc = _shrinking(c[i][0], c[i][1]);
            (uint256[] memory at,) = _seasonTf(inc, c[i][2]);
            (uint256[] memory above,) = _seasonTf(inc, c[i][2] + 100);
            assertEq(_falls(at), 0, "a fall at the opening the shrink allows");
            assertGt(_falls(above), 0, "no fall 1% above it");
        }
    }

    /// @dev Run TF's way, the case that bends is a crowd that keeps growing: the scaled anchor
    ///      asks for more each draw while the library forecasts this draw's income for the rest
    ///      of the season. The highest opening with no fall in the prize per ticket, 52 draws,
    ///      pinned from both sides. A crowd that doubles at once does not bend it.
    function test_tfAnchorASteadilyGrowingCrowdIsWhereItBends() public {
        uint256[3] memory rate = [uint256(10), 20, 30];  // tenths of a percent a draw
        uint256[3] memory most = [TF_GROW_1, TF_GROW_2, TF_GROW_3];
        for (uint256 i; i < 3; i++) {
            uint256[] memory inc = _growing(52, rate[i]);
            (uint256[] memory at,) = _seasonTf(inc, most[i]);
            (uint256[] memory above,) = _seasonTf(inc, most[i] + 100);
            assertEq(_ticketFalls(at, inc), 0, "a per-ticket fall at the opening the growth allows");
            assertGt(_ticketFalls(above, inc), 0, "no per-ticket fall 1% above it");
        }
        // Where it bends, it bends a little: 2% more players a draw at a 100% opening, and no
        // draw's prize per ticket is 1% below the one before.
        uint256[] memory g = _growing(52, 20);
        (uint256[] memory gp,) = _seasonTf(g, BPS);
        assertGt(_ticketFalls(gp, g), 0, "precondition: this growth bends the prize per ticket");
        for (uint256 i = 1; i < 52; i++) {
            assertGe(gp[i] * g[i - 1] * 100, gp[i - 1] * g[i] * 99, "a per-ticket fall of 1% or more");
        }
        uint256[] memory doubling = _exodus(52, 26, 0);
        for (uint256 d = 25; d < 52; d++) doubling[d] = 2 * WEEK;
        for (uint256 o = 100; o <= BPS; o += 1_100) {
            (uint256[] memory paid,) = _seasonTf(doubling, o);
            assertEq(_ticketFalls(paid, doubling), 0, "a crowd doubling at once lowered the prize per ticket");
        }
    }

    // ---------------------------------------------------------------- edges

    /// @dev A 0% opening pays nothing on draw 1, so draw 2 sees no last payment and is the
    ///      opening again, and so on: nothing is paid until the closing draw takes the pot.
    function test_aZeroOpeningPaysNothingUntilTheClose() public {
        (uint256[] memory paid, SeasonArc.Bind[] memory binds) = _season(_shrinking(12, 0), 0, 0, 0);
        for (uint256 i; i < 11; i++) {
            assertEq(paid[i], 0, "a zero opening paid something before the close");
            assertEq(uint256(binds[i]), uint256(SeasonArc.Bind.OPENING), "every draw before the close is an opening");
        }
        assertEq(uint256(binds[11]), uint256(SeasonArc.Bind.CLOSING));
        assertGt(paid[11], 0, "the closing draw pays the whole pot");
    }

    /// @dev The same happens when a non-zero opening of a tiny pot rounds down to nothing.
    function test_anOpeningThatRoundsToNothingRepeats() public pure {
        (uint256 a, SeasonArc.Bind b) = SeasonArc.size(9_999, 0, 10, 9_999, RET, 1);
        assertEq(a, 0, "1 bps of 9,999 units rounds to nothing");
        assertEq(uint256(b), uint256(SeasonArc.Bind.OPENING));
        (a, b) = SeasonArc.size(19_998, 0, 9, 9_999, RET, 1);
        assertEq(uint256(b), uint256(SeasonArc.Bind.OPENING), "so the next draw is the opening again");
        assertEq(a, 1, "and pays 1 unit once the pot is large enough");
    }

    /// @dev Half the pot leaves after draw 50 (a late jackpot win, say). The library steps
    ///      draw 51 down at every opening, from a quarter to 100%, and draw 52 does not fall
    ///      again: the dip comes from the money leaving, not from the opening.
    function test_aLateOutflowStepsTheNextDrawDownOnce() public {
        uint256[5] memory open = [uint256(2_500), 6_000, 7_500, 9_000, 10_000];
        for (uint256 j; j < 5; j++) {
            uint256 pot;
            uint256 last;
            uint256[] memory paid = new uint256[](52);
            for (uint256 d; d < 52; d++) {
                pot += WEEK + (pot * 400) / (52 * BPS);
                (uint256 a,) = SeasonArc.size(pot, last, 52 - d, WEEK, RET, open[j]);
                paid[d] = a;
                pot -= a;
                if (d + 1 < 52) pot += (a * RET) / BPS;
                last = a;
                if (d == 49) pot /= 2;
            }
            assertLt(paid[50], paid[49], "draw 51 steps down after the outflow");
            assertGe(paid[51], paid[50], "and the closing draw does not fall again");
            assertEq(_falls(paid), 1, "one step, at draw 51");
        }
    }
}
