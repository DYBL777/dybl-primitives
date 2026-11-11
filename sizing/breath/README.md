# Breath

A Solidity library that decides what each draw of a game with no end date can afford to pay,
from the game's live state: its income, its yield and what it paid last time.

**Pre-testnet. Not deployed, not audited.** The design and the mechanisms are the author's. AI was
the researcher, the economic modeller and the co-developer: writing the Solidity, each step
tested and reviewed before the next began. What is unproven or carried as a
known limit is in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## What it answers

    payout(state, config, pot, yieldWk, rhoBps) returns (amount, bind)

    pot       prize money on hand
    yieldWk   yield credited to the pot this draw
    rhoBps    the share of a prize that comes back to the pot (under 10,000)

    amount    what this draw may pay
    bind      which rule decided it: FLOOR, CREEP, BREAKEVEN, RISE_RAIL, FALL_RAIL, POT or DUST
              (a game not yet started, or an empty pot, reports DUST; with no income and
              minDraw at zero, a payout of 0 can come back as CREEP, so a host tests the
              amount, not the bind, to spot a draw that pays nothing)

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

Breath is one of two sizing solvers here, each for a different ending: Breath (no end date) and
SeasonArc (a rising arc to the last draw).

## Prior art

Breath was arrived at independently, from the question of what a pot with no end date can afford
each draw. We later found it shares its shape with endowment spending rules such as Yale's, which
blend last year's spending with a target rate so spending moves smoothly toward what the fund can
sustain. Breath does that on-chain, from live state, every draw. It differs in three ways: it
anchors on this draw's income and yield rather than a fixed share of the fund's value; its fast
average can be set to react faster to a fall than to a rise (the library refuses the reverse);
and there is no committee to step in, so the rule itself carries that job.

## Hosts

Lettery Perpetual, a weekly lottery with no end date, is the first host. It measures rhoBps from
its observed jackpot miss rate.

## Build and test

    forge install foundry-rs/forge-std@v1.16.2
    forge test

Compiler settings match the first host's, so the library tested here is the one it carries.
The dial values in the tests are Lettery Perpetual's; the model they were chosen on is `sim/` in
that game's repository.

`test/StandInGame.sol` is the smallest game that runs on Breath: a pot, income and yield each
draw, the payout Breath sizes, and `spare()` offered on a fixed rhythm. `test/StandIn.t.sol`
runs it for up to twenty years: a flat book opening at the floor and staying under breakeven,
payouts inside the rails over random income, a collapse gliding down on the fall rail, a pot
that `spare()` levels off where one nothing spends keeps growing, and a draw refused as dust
leaving the last real prize as the next draw's starting point.
