// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice THE RULE, CODED APART FROM THE LIBRARY, to judge what `size` paid mid-season. It
///         imports nothing, on purpose: `test-deployable/` compiles it beside the library, and what
///         else is in a compile can change the library's bytes (KNOWN_ISSUES).
library ArcRule {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant G_MAX = 1_000_000;  // the top of the library's search

    /// The rule as README.md states it: this draw's income is already in the pot and income is
    /// added before each later draw; a payment must be strictly under the balance before it;
    /// the returned share comes back after every draw but the last. Payments start at `first`
    /// grown by `g`. Returns the balance after the last draw, or 0 if a payment met the balance.
    function walk(uint256 pot, uint256 first, uint256 left, uint256 inc, uint256 ret, uint256 g)
        internal pure returns (uint256)
    {
        uint256 bal = pot;
        uint256 pay = first;
        for (uint256 k = 0; k < left; k++) {
            if (k != 0) bal += inc;
            pay = pay * g / BPS;
            if (pay >= bal) return 0;
            bal -= pay;
            if (k != left - 1) bal += pay * ret / BPS;
        }
        return bal;
    }

    uint8 internal constant ARC = 1;        // SeasonArc.Bind.ARC
    uint8 internal constant SUSTAINED = 2;  // SeasonArc.Bind.SUSTAINED

    /// Judges one mid-season answer (a last payment above zero, two or more draws left), with
    /// the bind passed as its number. Returns an empty string when the answer obeys the rule,
    /// or what it broke.
    function judge(
        uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret,
        uint256 amt, uint8 bind
    ) internal pure returns (string memory) {
        if (amt >= pot) return "a mid-season payment met the pot";
        if (bind == ARC) {
            // The growth factors that pay exactly `amt` run from gLo to gHi.
            uint256 gLo = (amt * BPS + last - 1) / last;
            uint256 gHi = ((amt + 1) * BPS + last - 1) / last - 1;
            if (walk(pot, last, left, inc, ret, gLo) == 0) return "the arc paid does not survive the season";
            if (gHi + 1 < G_MAX && walk(pot, last, left, inc, ret, gHi + 1) > 0) {
                return "a larger arc payment would have survived";
            }
            return "";
        }
        if (bind == SUSTAINED) {
            if (walk(pot, last, left, inc, ret, BPS) > 0) return "fell back although flat at the last payment survives";
            if (amt > 0 && walk(pot, amt, left, inc, ret, BPS) == 0) return "the flat payment does not survive";
            if (walk(pot, amt + 1, left, inc, ret, BPS) > 0) return "a larger flat payment would have survived";
            return "";
        }
        return "a mid-season call returned neither ARC nor SUSTAINED";
    }
}
