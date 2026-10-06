// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

/// @notice THE CLOSING-TO-OPENING RATIO, MEASURED RATHER THAN QUOTED. Two documents carried
///         two different figures for it and neither named a season length; a reader outside
///         this project then re-derived the arc independently and got a third answer at 104
///         draws that was far from ours. This file settles it from the shipped library.
contract ClosingRatio is Test {
    uint256 constant RET = 2990;

    function _ratio(uint256 draws) internal pure returns (uint256 first, uint256 last_) {
        uint256 pot; uint256 last; uint256 inc = 400_000e6;
        for (uint256 d = 1; d <= draws; d++) {
            pot += inc;
            (uint256 a, ) = SeasonArc.size(pot, last, draws - d + 1, inc, RET, 2_500);
            if (d == 1) first = a;
            last_ = a;
            pot -= a;
            if (draws - d + 1 > 1) pot += (a * RET) / 10_000;
            last = a;
        }
    }

    /// @dev Reported so the docs can quote a measured range with its lengths attached. At a
    ///      return share of 2,990 this model assumes the jackpot is missed every draw and the
    ///      other tiers pay out. A won jackpot returns less, and a tier that finds no winner and
    ///      returns its pool returns more, so this is neither a floor nor a ceiling on what a
    ///      real season pays at the close.
    function test_theRatioAtEachShippedSeasonLength() public {
        uint256[4] memory lengths = [uint256(12), 26, 52, 104];
        // The documented figures, x100, with a quarter-of-one-x tolerance. Change these only
        // together with the documents that quote them.
        uint256[4] memory expectedX100 = [uint256(1_415), 1_566, 1_641, 1_683];
        for (uint256 i; i < 4; i++) {
            (uint256 f, uint256 l) = _ratio(lengths[i]);
            emit log_named_uint("draws", lengths[i]);
            emit log_named_uint("  opening", f / 1e6);
            emit log_named_uint("  closing", l / 1e6);
            emit log_named_uint("  ratio x100", (l * 100) / f);
            // PINNED, NOT JUST EMITTED. This repository's README and Lettery TF's
            // ECONOMICS.md quote these four figures as measured from this file, and the only assertion here was that the close beats ten times
            // the opening: any drift that stayed above 10x left the documents quoting stale
            // numbers with nothing to catch it. A measured figure a document cites has to be
            // asserted where it is measured, or the citation is decoration.
            uint256 ratioX100 = (l * 100) / f;
            assertApproxEqAbs(ratioX100, expectedX100[i], 25,
                "the ratio this length is documented at has moved");
            assertGt(l, f * 10, "and the closing draw still dwarfs the opening");
        }
    }
}
