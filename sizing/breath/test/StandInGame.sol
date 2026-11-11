// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Breath} from "../src/Breath.sol";

/// @notice THE SMALLEST GAME THAT CAN RUN ON BREATH. It holds a pot, takes some income and yield
///         each draw, asks the library what to pay, pays it, offers the surplus out through
///         `spare()` on a fixed rhythm, and takes the returned share back. No tickets, no
///         randomness, no winners, no end: those are a host's business, and this exists so the
///         library's long-run behaviour can be watched without one.
/// @dev    What it does the way a real host does: income and yield land in the pot before the
///         library is asked, the income it observes is the income it just took, only the weekly
///         payout is committed (a surplus release is not, so it does not drag the next week up,
///         and a draw refused as dust is not, so the next draw steps from the last real prize),
///         and a share of every payment comes back to the pot. What it leaves out: a treasury
///         share, a weekly cap, a measured recycled share (this one is fixed at deploy), and a
///         host's own surplus policy. Lettery Perpetual, the first host, sizes its boosts itself
///         and does not call `spare()`; this one uses `spare()` instead, because the library says a
///         host should use one or the other, and on a flat book with yield a pot that nothing spends
///         keeps growing, which the tests show.
contract StandInGame {
    using Breath for Breath.State;

    uint256 internal constant BPS = 10_000;

    /// @notice Share of every payment that comes back to the pot.
    uint256 public immutable RETURN_BPS;
    /// @notice A surplus release is offered every this many draws; zero means never.
    uint256 public immutable SPARE_EVERY;
    /// @notice The caller's own ceiling on a release, as a share of the pot.
    uint256 public immutable SPARE_CEILING_BPS;

    Breath.State internal bs;
    Breath.Config internal cfg;

    uint256 public pot;
    uint256 public drawsDone;
    uint256[] public paid;
    uint256[] public spared;
    Breath.Bind[] public binds;

    error BadReturn();
    error BadSpare();

    constructor(Breath.Config memory c, uint256 returnBps, uint256 spareEvery, uint256 spareCeilingBps) {
        Breath.validate(c);
        if (returnBps >= BPS) revert BadReturn();
        if (spareEvery != 0 && (spareCeilingBps == 0 || spareCeilingBps > BPS)) revert BadSpare();
        cfg = c;
        RETURN_BPS = returnBps;
        SPARE_EVERY = spareEvery;
        SPARE_CEILING_BPS = spareCeilingBps;
    }

    /// @notice Runs one draw on `income` of new money and `yieldIn` of yield, and returns what it
    ///         paid, what bound the payout, and what it released from the surplus.
    function draw(uint256 income, uint256 yieldIn)
        external
        returns (uint256 amount, Breath.Bind bind, uint256 released)
    {
        pot += income + yieldIn;
        bs.observe(cfg, income);
        (amount, bind) = bs.payout(cfg, pot, yieldIn, RETURN_BPS);
        // Checked arithmetic: a payment larger than the pot reverts here, which is what the
        // tests rely on to catch one.
        pot -= amount;
        drawsDone += 1;
        if (SPARE_EVERY != 0 && drawsDone % SPARE_EVERY == 0) {
            released = Breath.spare(cfg, pot, amount, SPARE_CEILING_BPS);
            pot -= released;
        }
        pot += ((amount + released) * RETURN_BPS) / BPS;
        if (amount != 0) bs.commit(amount);
        paid.push(amount);
        spared.push(released);
        binds.push(bind);
    }

    function paidCount() external view returns (uint256) { return paid.length; }
    function lastPaid() external view returns (uint256) { return bs.lastPaid; }
    function fast() external view returns (uint256) { return bs.fast; }
    function slow() external view returns (uint256) { return bs.slow; }
}
