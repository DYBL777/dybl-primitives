// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

/// @notice Calls the library from outside, so a revert can be caught.
contract VectorHost {
    function size(uint256 pot, uint256 last, uint256 dl, uint256 inc, uint256 ret, uint256 open)
        external pure returns (uint256 amount, uint8 bind)
    {
        SeasonArc.Bind b;
        (amount, b) = SeasonArc.size(pot, last, dl, inc, ret, open);
        bind = uint8(b);
    }
}

/// @notice The compiled library against every case in lab/vectors.json: the same amount, the same
///         bind, and a revert where the file records one. lab/seasonarc.js, the JavaScript port the
///         Season Lab runs, is held to the same file (`node lab/seasonarc.js check`), so a passing
///         run here and there means the port and the library agree on all of them.
contract Vectors is Test {
    struct Case {
        uint256 pot; uint256 last; uint256 dl; uint256 inc; uint256 ret; uint256 open;
    }

    function test_theLibraryGivesEveryPublishedAnswer() public {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/lab/vectors.json"));
        uint256 count = vm.parseJsonUint(json, ".count");
        uint256[] memory pot = vm.parseJsonUintArray(json, ".pot");
        uint256[] memory last = vm.parseJsonUintArray(json, ".lastPaid");
        uint256[] memory dl = vm.parseJsonUintArray(json, ".drawsLeft");
        uint256[] memory inc = vm.parseJsonUintArray(json, ".income");
        uint256[] memory ret = vm.parseJsonUintArray(json, ".returnBps");
        uint256[] memory open = vm.parseJsonUintArray(json, ".openingBps");
        uint256[] memory amount = vm.parseJsonUintArray(json, ".amount");
        uint256[] memory bind = vm.parseJsonUintArray(json, ".bind");
        uint256[] memory reverts = vm.parseJsonUintArray(json, ".reverts");
        assertEq(pot.length, count, "every column has a value per case");
        assertGt(count, 1_000, "the file has its cases");

        VectorHost h = new VectorHost();
        uint256 reverted;
        for (uint256 i = 0; i < count; i++) {
            try h.size(pot[i], last[i], dl[i], inc[i], ret[i], open[i]) returns (uint256 a, uint8 b) {
                assertEq(reverts[i], 0, string.concat("the library answered where the file records a revert, case ", vm.toString(i)));
                assertEq(a, amount[i], string.concat("amount, case ", vm.toString(i)));
                assertEq(uint256(b), bind[i], string.concat("bind, case ", vm.toString(i)));
            } catch {
                assertEq(reverts[i], 1, string.concat("the library reverted where the file records an answer, case ", vm.toString(i)));
                reverted++;
            }
        }
        assertGt(reverted, 0, "the revert cases are reached");
    }
}
