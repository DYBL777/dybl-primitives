// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SeasonArc} from "../src/SeasonArc.sol";
import {ArcRule} from "../test/ArcRule.sol";

contract DeployableHost {
    function size(uint256 pot, uint256 last, uint256 left, uint256 inc, uint256 ret)
        external pure returns (uint256 a, uint8 b)
    { SeasonArc.Bind bind; (a, bind) = SeasonArc.size(pot, last, left, inc, ret, 2_500); b = uint8(bind); }
}

/// @notice THE BUILD THAT DEPLOYS, TESTED. Run with `FOUNDRY_PROFILE=deployable forge test`.
///         Nothing here imports forge-std, and this folder sorts after `src/`, so the compile
///         puts nothing ahead of the library and it comes out as the build a deployment uses
///         (KNOWN_ISSUES). The default `forge test` runs the other build. Failures here revert
///         with the rule broken.
contract DeployableBuild {
    /// The library built on its own (`forge build --skip test`), in runtime bytes. The same
    /// figure is in README.md and moves with any change to the library or its settings.
    uint256 constant DEPLOYABLE_BYTES = 1_310;

    DeployableHost h;

    function setUp() public { h = new DeployableHost(); }

    /// The library under test is the deployable build. If this fails while the library is
    /// unchanged, an edit to this folder has changed what the compiler emits for the library
    /// (KNOWN_ISSUES), and the rest of this file is no longer testing the build that deploys.
    function test_theLibraryUnderTestIsTheDeployableBuild() public view {
        require(address(SeasonArc).code.length == DEPLOYABLE_BYTES, "not the deployable build");
    }

    function grid(uint256 left, uint256 potU, uint256 lastU, uint256 incU, uint256 jitter) internal view {
        uint256[5] memory incs = [uint256(0), 1, 3, 10, 40];
        uint256[5] memory rets = [uint256(0), 1, 2_990, 5_000, 9_999];
        for (uint256 pot = 1; pot <= 40; pot++) {
            for (uint256 last = 1; last <= 40; last++) {
                for (uint256 a = 0; a < 5; a++) {
                    for (uint256 b = 0; b < 5; b++) {
                        uint256 p = pot * potU + jitter * pot;
                        uint256 l = last * lastU + jitter;
                        (uint256 amt, uint8 bind) = h.size(p, l, left, incs[a] * incU, rets[b]);
                        string memory why = ArcRule.judge(p, l, left, incs[a] * incU, rets[b], amt, bind);
                        require(bytes(why).length == 0, why);
                    }
                }
            }
        }
    }

    /// The edges, as the Halmos proofs state them, on sample inputs.
    function test_theEdgesHold() public view {
        (uint256 a, uint8 b) = h.size(1_000e6, 77e6, 1, 5e6, 2_990);
        require(a == 1_000e6 && b == 4, "the last draw pays the whole pot, CLOSING");
        (a, b) = h.size(1_000e6, 0, 10, 5e6, 2_990);
        require(a == 250e6 && b == 0, "the opening is its share, OPENING");
        (a, b) = h.size(1_000e6, 77e6, 0, 5e6, 2_990);
        require(a == 0 && b == 3, "no draws left pays nothing, POT");
    }

    function test_tinyPotsTwoDrawsLeft() public view { grid(2, 1, 1, 1, 0); }
    function test_tinyPotsSixDrawsLeft() public view { grid(6, 1, 1, 1, 0); }
    function test_tinyPotsTwelveDrawsLeft() public view { grid(12, 1, 1, 1, 0); }
    function test_moneyTwelveDrawsLeft() public view { grid(12, 1_000e6, 50e6, 100e6, 7); }
    function test_moneyFiftyTwoDrawsLeft() public view { grid(52, 1_000e6, 50e6, 100e6, 7); }
}
