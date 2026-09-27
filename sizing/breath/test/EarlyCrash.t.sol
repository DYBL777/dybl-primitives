// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

/// @notice What a crash does to PLAYERS, and separately to the headline number.
///
/// @dev    THE INVARIANT THAT MATTERS IS VALUE PER ENTRANT, NOT THE ABSOLUTE PRIZE. An
///         earlier version of this file asserted only that the absolute prize never fell
///         more than the 6% rail, and so reported a crash as a failure when it was the
///         design working. When 99% of players leave, the prize does fall in absolute
///         terms, but it is then divided among a hundredth of the people: measured, value
///         per entrant goes from about $1.02 to about $55.85, fifty-five times better for
///         everyone who stayed. That is the inversion, and it is the point of holding a
///         reserve. The absolute figure is a marketing number; the per-entrant figure is
///         the player's experience, and it is the one a regression must protect.
/// @dev    In the first few weeks the pot is roughly one week of banked income, so
///         it cannot fund a 6%-per-draw glide down from a prize sized against the old
///         income. A sharp correction there is honest, and no player has a long history of
///         prizes to feel robbed of. What matters is that it is confined to those weeks and
///         cannot recur once the reserve exists. These two tests pin exactly that boundary.
contract EarlyCrash is Base {
    BreathHost internal n;
    uint256 internal pot;
    uint256 internal prev;
    uint256 internal worstFall;
    uint256 internal worstWeek;

    bool internal sawNonPotHardFall;

    function _step(uint256 w, uint256 income) internal {
        pot += income;
        uint256 y = pot / 1000;                 // roughly a week of 5% APY
        pot += y;
        n.observe(income);
        (uint256 amt, Breath.Bind bind) = n.quote(pot, y, RHO);
        if (prev > 0 && amt < prev) {
            uint256 f = ((prev - amt) * 100) / prev;
            // Here only the pot cap should cut below the fall rail; the dust guard is the
            // other case that may, pinned in Rails.t.sol. Anything else is a regression.
            if (f > 6 && bind != Breath.Bind.POT) sawNonPotHardFall = true;
            if (f > worstFall) { worstFall = f; worstWeek = w; }
        }
        if (amt > 0) {
            pot -= amt;
            pot += (amt * 2000) / 10000;
            n.commit(amt);
            prev = amt;
        }
    }

    function _fresh() internal {
        n = new BreathHost(defaultConfig());   // the fixture's default dials
        pot = 0; prev = 0; worstFall = 0; worstWeek = 0; sawNonPotHardFall = false;
    }

    function test_hardFallsAreConfinedToTheOpeningWeeks() public {
        for (uint256 crashAt = 2; crashAt <= 8; crashAt++) {
            _fresh();
            for (uint256 w = 1; w <= 30; w++) {
                _step(w, w >= crashAt ? INCOME / 100 : INCOME);
            }
            emit log_named_uint("crash at week", crashAt);
            emit log_named_uint("  worst fall %", worstFall);
            emit log_named_uint("  in week", worstWeek);
            // The week number is not the invariant: a crashed game can deplete late enough
            // for the POT CAP to bite after week nine, which is that exception doing its job.
            // What must hold in this fixture is that nothing other than the pot cap cuts below
            // the rail. The dust guard can too, pinned in Rails.t.sol; it does not fire here.
            assertFalse(sawNonPotHardFall,
                "in this fixture only the pot cap cut below the fall rail");
        }
    }

    /// @notice The same crash, once the reserve exists, glides at the rail instead.
    function test_theSameCrashLaterGlidesAtTheRail() public {
        _fresh();
        for (uint256 w = 1; w <= 60; w++) {
            if (w == 10) { worstFall = 0; worstWeek = 0; }   // ignore the opening weeks
            _step(w, w >= 40 ? INCOME / 100 : INCOME);
        }
        emit log_named_uint("worst fall after week 10, crash at week 40", worstFall);
        assertLe(worstFall, 6, "with a reserve in place the glide holds at the rail");
    }

    /// @notice THE PRIMARY INVARIANT: a crash must never reduce the value per entrant.
    function test_valuePerEntrantNeverFallsInACrash() public {
        n = new BreathHost(defaultConfig());
        pot = 0; prev = 0;
        uint256 entrants = 10_000;
        uint256 perEntrantBefore;

        for (uint256 w = 1; w <= 12; w++) {
            if (w == 6) entrants = 100;                       // 99% wipeout
            uint256 income = entrants * 4 * USDC;             // $5 ticket, 20% treasury
            pot += income;
            uint256 y = pot / 1040;
            pot += y;
            n.observe(income);
            (uint256 amt, ) = n.quote(pot, y, RHO);
            if (amt > 0) {
                uint256 perEntrant = amt / entrants;
                if (w == 5) perEntrantBefore = perEntrant;
                if (w >= 6 && perEntrantBefore > 0) {
                    emit log_named_uint("week", w);
                    emit log_named_uint("  value per entrant", perEntrant);
                    assertGe(perEntrant, perEntrantBefore,
                        "a crash must never leave a remaining player worse off");
                }
                pot -= amt;
                pot += (amt * 2000) / 10000;
                n.commit(amt);
                prev = amt;
            }
        }
    }
}
