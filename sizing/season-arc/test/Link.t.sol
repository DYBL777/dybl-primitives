// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";

contract LinkHost {
    function size(uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret)
        external pure returns (uint256, SeasonArc.Bind)
    { return SeasonArc.size(pot, last, left, inc, ret, 2_500); }
}

/// @notice WHAT A DEPLOYER CAN CHECK ABOUT THE LINKED COPY. A host runs whatever code sits at
///         the address it was linked to (KNOWN_ISSUES), so these pin what that code looks like
///         and what a host does when the address is wrong.
contract Link is Test {
    /// One build, one code hash. SeasonArc has no state-changing function, so the compiler
    /// writes no address into it, and every deployed copy of a build is byte-identical. A
    /// host's deploy can compare the linked address's code hash against the build it trusts.
    /// Two fresh copies are deployed here, at addresses of their own, beside the linked one.
    function test_everyCopyOfABuildHasTheSameCodeHash() public {
        address one = deployFresh();
        address two = deployFresh();
        assertTrue(one != two && one != address(SeasonArc), "three separate copies");
        assertGt(one.code.length, 0, "the copy has code");
        assertEq(one.codehash, two.codehash);
        assertEq(one.codehash, address(SeasonArc).codehash);
        emit log_named_uint("runtime bytes in this build", one.code.length);
        emit log_named_bytes32("code hash of this build", one.codehash);
    }

    function deployFresh() internal returns (address a) {
        bytes memory c = type(SeasonArc).creationCode;
        assembly { a := create(0, add(c, 32), mload(c)) }
        require(a != address(0), "deploy failed");
    }

    /// Linked to an address with no code, the host reverts. It does not read the empty reply
    /// as a payment of zero.
    function test_aHostLinkedToAnEmptyAddressReverts() public {
        LinkHost host = new LinkHost();
        (uint256 before,) = host.size(1_000e6, 100e6, 10, 0, 0);
        assertGt(before, 0, "the host works while the library is there");
        vm.etch(address(SeasonArc), "");
        vm.expectRevert();
        host.size(1_000e6, 100e6, 10, 0, 0);
    }

    /// Called directly rather than through a host, the library answers and changes nothing:
    /// `size` is pure, so a stranger's call reads and writes no storage anywhere.
    function test_aDirectCallAnswersAndChangesNothing() public view {
        (bool ok, bytes memory r) = address(SeasonArc).staticcall(abi.encodeWithSelector(
            SeasonArc.size.selector, uint256(1_000e6), uint256(0), uint256(10), uint256(0), uint256(0), uint256(2_500)));
        assertTrue(ok);
        (uint256 amt,) = abi.decode(r, (uint256, uint8));
        assertEq(amt, 250e6, "the opening: 25% of 1,000");
    }
}
