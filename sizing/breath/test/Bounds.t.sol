// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {Base, BreathHost} from "./Base.t.sol";
import {Breath} from "../src/Breath.sol";
contract Bounds is Base {
    function test_aHighFloorIsRejectedAtDeploy() public {
        Breath.Config memory c = defaultConfig();
        c.floorBps = 5500;                       // the superseded pairing
        vm.expectRevert(Breath.BadShare.selector);
        new BreathHost(c);
    }
    /// @dev A share of 100% would let one ask take the entire surplus, which empties the
    ///      band in a single call and leaves nothing for the next ask to descend from. The
    ///      emergent ladder depends on each call taking only a part.
    function test_aSpareShareOfTheWholeSurplusIsRejectedAtDeploy() public {
        Breath.Config memory c = defaultConfig();
        c.spareShareBps = 10_000;
        vm.expectRevert(Breath.BadCover.selector);
        new BreathHost(c);
    }
}
