// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

/// @dev Reaches the linked library the way a host does.
contract ProofHost {
    function size(uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret, uint256 open)
        external pure returns (uint256, SeasonArc.Bind)
    { return SeasonArc.size(pot, last, left, inc, ret, open); }
}

/// @notice Symbolic proofs, run with Halmos (`halmos --contract SeasonArcProofs`), not with
///         `forge test`. Each `check_` function is proved for every input in its stated range;
///         forge ignores them. These are the edges of `size`: the closing draw, the opening,
///         an empty season and the two input guards. The solver's search for a mid-season
///         payment is too deep for a symbolic proof (a 2-draw version with figures under 2**16
///         did not finish in 4.5 minutes) and is covered by the fuzz, exhaustive and invariant
///         tests instead.
contract SeasonArcProofs is Test {
    ProofHost h;

    function setUp() public { h = new ProofHost(); }

    /// No draws left: nothing to pay, labelled POT.
    function check_noDrawsLeftPaysNothing(uint256 pot, uint256 last, uint256 inc, uint256 ret, uint256 open)
        public view
    {
        vm.assume(ret < 10_000 && open <= 10_000);
        (uint256 a, SeasonArc.Bind b) = h.size(pot, last, 0, inc, ret, open);
        assertEq(a, 0);
        assertEq(uint256(b), uint256(SeasonArc.Bind.POT));
    }

    /// The last draw pays the whole pot, labelled CLOSING, whatever else is passed.
    function check_lastDrawPaysTheWholePot(uint256 pot, uint256 last, uint256 inc, uint256 ret, uint256 open)
        public view
    {
        vm.assume(ret < 10_000 && open <= 10_000);
        (uint256 a, SeasonArc.Bind b) = h.size(pot, last, 1, inc, ret, open);
        assertEq(a, pot);
        assertEq(uint256(b), uint256(SeasonArc.Bind.CLOSING));
    }

    /// The first draw of a season pays exactly the opening share of the pot, labelled OPENING.
    /// Proved for pots under 2**128 and 2 to 1,000 draws left.
    function check_openingPaysTheShareOfThePot(uint256 pot, uint256 left, uint256 inc, uint256 ret, uint256 open)
        public view
    {
        vm.assume(ret < 10_000 && open <= 10_000);
        vm.assume(pot > 0 && pot < 2 ** 128 && left >= 2 && left <= 1_000);
        (uint256 a, SeasonArc.Bind b) = h.size(pot, 0, left, inc, ret, open);
        assertEq(a, pot * open / 10_000);
        assertEq(uint256(b), uint256(SeasonArc.Bind.OPENING));
    }

    /// A return share of 10,000 or more is refused.
    function check_returnShareOfTheWholeIsRefused(
        uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret, uint256 open
    ) public view {
        vm.assume(ret >= 10_000);
        try h.size(pot, last, left, inc, ret, open) { assert(false); } catch {}
    }

    /// An opening share above 10,000 is refused.
    function check_openingShareAboveTheWholeIsRefused(
        uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret, uint256 open
    ) public view {
        vm.assume(ret < 10_000 && open > 10_000);
        try h.size(pot, last, left, inc, ret, open) { assert(false); } catch {}
    }
}
