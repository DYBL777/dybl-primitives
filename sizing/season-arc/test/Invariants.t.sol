// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SeasonArc} from "../src/SeasonArc.sol";
import {StandInGame} from "./StandInGame.sol";

/// @notice Runs season after season through the stand-in game, driven by the invariant runner.
///         Each season draws its own length, opening share and return share; each draw's income
///         swings with a crowd that can arrive, leave, or stop buying altogether. Every rule the
///         library states about a single payment is checked on every draw, and a broken rule is
///         recorded for the invariants below.
contract ArcHandler is Test {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant USUAL = 40_000e6;

    StandInGame public game;
    uint256 public openingBps;
    uint256 public returnBps;
    uint256 public crowdBps = BPS;   // income level as a share of the usual

    uint256 public seasonIncome;     // this season's income
    uint256 public seasonOut;        // this season's payments, less the share that came back
    uint256 public seasonsFinished;

    bool public paidMoreThanPot;
    bool public openingWrong;
    bool public arcSizedDown;
    bool public arcReachedThePot;
    bool public closingWrong;
    bool public closingLeftMoney;

    constructor() {
        _newSeason(52, 2_500, 2_990);
    }

    function _newSeason(uint256 draws, uint256 opening, uint256 ret) internal {
        game = new StandInGame(draws, opening, ret);
        openingBps = opening;
        returnBps = ret;
        seasonIncome = 0;
        seasonOut = 0;
    }

    /// Start a fresh season with random length, opening share and return share.
    function startSeason(uint8 drawsSeed, uint16 openingSeed, uint16 returnSeed) external {
        _newSeason(bound(drawsSeed, 2, 104), bound(openingSeed, 1_000, 5_000), bound(returnSeed, 0, 5_000));
    }

    /// The crowd changes size: from nobody to three times the usual.
    function crowd(uint16 levelSeed) external {
        crowdBps = bound(levelSeed, 0, 30_000);
    }

    /// One draw, with income around the crowd's level.
    function draw(uint256 jitterSeed) external {
        if (game.drawsDone() == game.DRAWS()) {
            _newSeason(game.DRAWS(), openingBps, returnBps);
        }
        uint256 base = (USUAL * crowdBps) / BPS;
        uint256 income = base == 0 ? 0 : bound(jitterSeed, (base * 8) / 10, (base * 12) / 10);

        uint256 left = game.DRAWS() - game.drawsDone();
        uint256 last = game.lastPaid();
        uint256 potBefore = game.pot() + income;

        (uint256 amount, SeasonArc.Bind bind) = game.draw(income);
        seasonIncome += income;

        if (amount > potBefore) paidMoreThanPot = true;
        if (left == 1) {
            if (bind != SeasonArc.Bind.CLOSING || amount != potBefore) closingWrong = true;
            if (game.pot() != 0) closingLeftMoney = true;
            seasonsFinished++;
            seasonOut += amount;
        } else {
            seasonOut += amount - (amount * returnBps) / BPS;
        }
        if (bind == SeasonArc.Bind.OPENING && amount != (potBefore * openingBps) / BPS) openingWrong = true;
        if (bind == SeasonArc.Bind.ARC) {
            if (amount < last) arcSizedDown = true;
            if (amount >= potBefore) arcReachedThePot = true;
        }
    }
}

/// @notice Rules that hold across any run of seasons, checked by Foundry's invariant runner.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 120
/// forge-config: default.invariant.fail-on-revert = true
contract SeasonArcInvariants is Test {
    ArcHandler internal h;

    function setUp() public {
        h = new ArcHandler();
        targetContract(address(h));
    }

    /// @notice No draw pays more than the pot holds. The stand-in also subtracts each payment
    ///         with checked arithmetic, and fail-on-revert turns an overdraw into a failure.
    function invariant_noDrawPaysMoreThanThePot() public view {
        assertFalse(h.paidMoreThanPot(), "paid more than the pot");
    }

    /// @notice The opening draw pays exactly its opening share of the pot.
    function invariant_theOpeningIsItsShare() public view {
        assertFalse(h.openingWrong(), "opening was not its share of the pot");
    }

    /// @notice On the solved arc the library grows or holds the payment; it does not size down.
    ///         Only the fallback (SUSTAINED), an empty pot or the closing draw can pay less.
    function invariant_theArcDoesNotSizeDown() public view {
        assertFalse(h.arcSizedDown(), "the arc paid less than the last draw");
    }

    /// @notice Before the closing draw, an arc payment is less than the whole pot.
    function invariant_theArcLeavesSomethingForLater() public view {
        assertFalse(h.arcReachedThePot(), "an arc payment took the whole pot early");
    }

    /// @notice The closing draw takes everything left, and the stand-in's pot ends at zero.
    function invariant_theClosingDrawEmptiesThePot() public view {
        assertFalse(h.closingWrong(), "the closing draw did not take the whole pot");
        assertFalse(h.closingLeftMoney(), "money was left after the closing draw");
    }

    /// @notice Within a season, every unit of income was paid out or is still in the pot.
    function invariant_everyUnitIsAccountedFor() public view {
        assertEq(h.seasonIncome(), h.seasonOut() + h.game().pot(), "season accounting");
    }
}
