// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";

/// @notice The early returns and the refused input: a game that has not started, an empty pot,
///         a return share of the whole, and the three cases where `spare` offers nothing.
contract Edges is Base {

    /// @notice Before the first observation, a quote pays nothing and says DUST, whatever the pot.
    function test_aGameThatHasNotStartedPaysNothing() public {
        BreathHost fresh = new BreathHost(defaultConfig());
        (uint256 amount, Breath.Bind bind) = fresh.quote(10_000_000 * USDC, 5_000 * USDC, RHO);
        assertEq(amount, 0, "nothing before the first observation");
        assertEq(uint256(bind), uint256(Breath.Bind.DUST), "and says DUST, not POT");
    }

    /// @notice A started game with an empty pot pays nothing and says DUST.
    function test_anEmptyPotPaysNothing() public {
        settle(INCOME, 60);
        (uint256 amount, Breath.Bind bind) = h.quote(0, 5_000 * USDC, RHO);
        assertEq(amount, 0, "nothing from an empty pot");
        assertEq(uint256(bind), uint256(Breath.Bind.DUST), "and says DUST, not POT");
    }

    /// @notice A return share of the whole prize is refused: breakeven would be unbounded.
    function test_aReturnShareOfTheWholeIsRefused() public {
        settle(INCOME, 60);
        vm.expectRevert(Breath.BadRho.selector);
        h.quote(10_000_000 * USDC, 0, 10_000);
    }

    /// @notice `spare` offers the smaller of its share of the surplus and the caller's ceiling,
    ///         and nothing with no weekly prize to cover, with a ceiling of zero, or with the pot
    ///         at or under the cover target.
    function test_spareOffersTheSmallerLimitAndNothingWithoutASurplus() public {
        settle(INCOME, 60);
        uint256 weekly = 1_000_000 * USDC;
        uint256 reserve = 40 * weekly;                  // coverTarget in the fixture
        uint256 rich = reserve + 100_000_000 * USDC;
        uint256 share = defaultConfig().spareShareBps;
        assertEq(h.spare(rich, weekly, 10_000), ((rich - reserve) * share) / 10_000,
            "with a high ceiling: the share of the surplus above the cover target");
        assertEq(h.spare(rich, weekly, 100), (rich * 100) / 10_000,
            "with a low ceiling: the ceiling's share of the pot");
        assertEq(h.spare(rich, 0, 10_000), 0, "no weekly prize to cover");
        assertEq(h.spare(rich, weekly, 0), 0, "a ceiling of zero");
        assertEq(h.spare(reserve, weekly, 10_000), 0, "the pot exactly at the cover target");
        assertEq(h.spare(reserve - 1, weekly, 10_000), 0, "the pot under it");
    }
}
