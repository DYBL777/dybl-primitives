# Breath

A Solidity library that decides what each draw of a game with no end date can afford to pay,
from the game's live state: its income, its yield and what it paid last time.

**Pre-testnet. Not deployed, not audited.** The design and the maths are the author's; the
Solidity was written with AI assistance under that direction. What is unproven or carried as a
known limit is in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## What it answers

    payout(state, config, pot, yieldWk, rhoBps) returns (amount, bind)

    pot       prize money on hand
    yieldWk   yield credited to the pot this draw
    rhoBps    the share of a prize that comes back to the pot (under 10,000)

    amount    what this draw may pay
    bind      which rule decided it: FLOOR, CREEP, BREAKEVEN, RISE_RAIL, FALL_RAIL, POT or DUST
              (a game not yet started, or an empty pot, reports DUST)

The host also calls `observe(net)` once per draw to fold that draw's income into two running
averages, and `commit(paid)` to record the regular prize the next draw steps from. `spare()` is
optional: it tells a host how much it could take on top without eating into the reserve.

## The rule, in plain words

- **Breakeven is the anchor.** It is the payout that spends recent income (a fast-moving average)
  plus this draw's yield, once the share that comes back to the pot is counted. When income is
  running at that average, paying less grows the pot and paying more shrinks it.
- **Pace moves with the trend.** When recent income is running below the long-run average the
  game pays a smaller share of breakeven; when it is running above, a larger share.
- **Prizes creep up from the last one,** from a floor set from income, and are capped at
  breakeven at the current pace. The rails apply after that cap, so a falling prize can sit above
  breakeven for a while as it glides down.
- **Rails limit each step.** A prize may rise or fall only so far in one draw. Apart from the pot
  running short, the only thing that may cut harder than the fall rail is the dust guard: a draw
  sized under the minimum pays nothing.

The reasoning behind each rule is in the comments of [src/Breath.sol](src/Breath.sol).

## Using it

**Breath is internal,** so a host compiles its own copy rather than calling a deployed one.

**What the host is trusted to pass.** The library cannot see the host's books. A host that passes
a return share it does not actually return gets a confident wrong answer.

**What it does not do.** It knows nothing of tickets, tiers or winners, and it does not decide when
anything happens. It returns an amount; the host decides how that amount is split and paid.

## Siblings

Breath is one of four sizing solvers, each for a different ending: BreathEngine (reach a floor by
a deadline), Breath (no end date), SeasonArc (a rising arc to the last draw) and SeedGlide
(equal shares down to zero).

## Hosts

Lettery Perpetual, a weekly lottery with no end date, is the first host. It measures rhoBps from
its observed jackpot miss rate.

## Build and test

    forge install foundry-rs/forge-std@v1.16.2
    forge test

Compiler settings match the first host's, so the library tested here is the one it carries.
