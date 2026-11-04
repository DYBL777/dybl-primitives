# SeasonArc: design

Why the library is shaped the way it is. What it does is in [README.md](README.md), and its
limits are in [KNOWN_ISSUES.md](KNOWN_ISSUES.md). This file holds the reasoning: what each rule
is for, what was tried and rejected, and where each claim is tested.

## The problem

A pot of money must be paid out over a season with a known last draw, decided by the contract
rather than a person. This is one form of the Autonomous Distribution Rate Problem (ADRP):
paced, autonomous distribution from a fixed-term pot. The pot keeps being fed during the season,
because tickets keep being sold, and nobody knows in advance how many.

The library aims at three things together:

- **A real first prize.** The first host pays out ticket money, and its smallest tier has to be
  worth more than a ticket from the first draw. The library sizes the draw's total; the host's
  prize split and roll-down decide how that payment reaches the smallest tier.
- **Payments that rise** across the season, so the biggest draws come at the end.
- **The pot spent by the last draw,** whatever the crowd did along the way.

## The rule

The first draw pays a set share of the pot. Every later draw pays the last payment times a
growth factor `g`, and `g` is solved fresh every draw so that carrying on at that growth spends
the pot by the last draw. The last draw pays the whole pot. If even flat payments would run the
pot dry, the draw pays the largest flat amount the pot and its future income can carry to the
end. The README has the full rule in plain words.

## Decisions

Each decision below gives the rule, the reason, and what it replaced or was chosen over.

### Grow from the last payment, rather than split the pot equally

**Rule.** Each payment is the last one times `g`.

**Why.** An equal-share rule (pot divided by draws left) also rises across a season, because the
pot grows while the divisor shrinks, and it needs no solver. It only works when the first draw is
allowed to be tiny, which suits a game paying out yield on parked money: nobody expects much in
week one. A ticket-funded game cannot open that small, because its smallest prize must be worth
a ticket from the start. Force a real opening onto an equal-share rule and a large part of the pot
is spent early, after which equal shares fall rather than rise. Growing from the last payment
and solving for the ending gives both a real opening and a rise.

**Chosen over.** The equal-share glide. It is a sound rule for yield-funded pots and lives in
this family under its own name, SeedGlide.

### Re-solve `g` every draw

**Rule.** The growth factor is solved again on every draw from the pot as it stands.

**Why.** The pot is fed by ticket income, which moves. A factor fixed at the start against an
assumed crowd would strand money if more people came, or run the pot dry before the end if fewer
did. Re-solving lets the arc bend to what actually happened. The only forecast it makes is that
the income just seen keeps arriving.

**Chosen over.** A growth factor fixed at deploy.

### One dial: the opening share

**Rule.** The opening share is the only setting. It decides both the size of the first prize
and how steep the climb is after it.

**Why.** A larger opening leaves less for the climb, so it gives a flatter arc, and a smaller one
gives a steeper arc. One setting makes the trade-off visible and leaves nothing else to tune.

### No rails on how far a payment can move

**Rule.** Unlike Breath, nothing limits how far one draw can move from the last.

**Why.** Breath needs rails because its payout follows income, and income can crash. Here the
payment is a share of a stock. Within a few draws the pot is much larger than the weekly income,
so a collapse in sales moves the pot slowly while the number of draws left falls by one every
draw regardless. Measured with the last payment passed in unscaled, as the stand-in game does, a
collapse gives one step down and then flat payments (see Evidence). A host that scales the last
payment by the change in crowd (Lettery TF does) steps down by that ratio and climbs from there.
On the way up, a rail would have nothing to catch.

**Chosen over.** The rise and fall rails of the perpetual rule.

### The last draw is answered before the empty pot

**Rule.** With one draw left, the library returns the whole pot as `CLOSING`, even when the pot
is empty.

**Why.** An earlier order tested for an empty pot first, and on the last draw it returned `POT`
with nothing to pay. That reads as "no draw to size", when the truth is "the last draw, and the
pot is empty". A host that refuses a zero-sized draw then cannot end its season. The amount is
the same either way; the label is what a host acts on.

### The fallback fires only when the arc has failed

**Rule.** When the solver bottoms out at flat, the library first checks whether flat payments
still fit. If they do, it pays the last amount again (`ARC`). Only if flat runs the pot dry does
it pay the fallback (`SUSTAINED`).

**Why.** The solver returns its floor in two different cases: flat growth running the pot dry,
and flat growth fitting while nothing steeper does. Only the first is a failed arc. Before this
check, both were sent to the fallback, so an arc that had merely flattened was paid as if it had
failed.

**Chosen over.** Gating the fallback on the payment falling below an equal share of the pot. A
healthy arc deliberately pays less than an equal share early, which is what makes the last draw
large. And when the pot is draining, the last payment is larger than an equal share, so that
gate could not fire in the case it existed for.

### The fallback counts the income still to come

**Rule.** The fallback pays the largest flat amount the pot and its future income can carry to
the end.

**Why.** The first fallback paid `pot / drawsLeft`, which spreads today's pot across the draws
left as if no more tickets would be sold. A growing crowd could then see its payment fall and
not recover. On a pot of $28,744 with eight draws left and $4,000 a draw still arriving, at a
29.9% return share, the old rule pays $3,593 where $9,606.23 can be carried.

**Chosen over.** `pot / drawsLeft`.

### The fallback is solved by formula, then corrected

**Rule.** The largest flat payment comes from a closed formula, and a short search corrects it
when rounding makes the formula miss.

**Why.** With flat payments, the pot's path is a straight line, so the limit can be written down.
The payment must stay under what stands before each draw, and the tightest of those limits is
at the first draw or the last, so only those two need checking. Integer rounding of the
returned share can leave the formula a few units too high, at most one per draw left, so a small
search over that band finds the exact answer. The forward walk, not the formula, has the final
say.

**Chosen over.** A bisection search. It needed an upper bound to search under, and the only one
available was arbitrary. At very large figures it also stopped resolving to the unit: at a pot of
1e30 it undershot the true answer by about 1e12. The formula is exact there.

### A high ceiling on the growth search

**Rule.** The search for `g` runs from flat up to 100 times per draw.

**Why.** The ceiling is the top of the search, not a safety limit. Every step of the forward walk
is already checked against the pot, so a steep candidate is rejected by the same test as any
other. A low ceiling only shuts the solver out of answers it needs: a crowd arriving mid-season
can want growth above a doubling, and with a ceiling at a doubling, an isolated call can return
that ceiling rather than the solved answer.

**Chosen over.** A ceiling of a doubling per draw.

### The last draw's returned share is left out of the forecast

**Rule.** The forward walk takes back no returned share on the last remaining draw.

**Why.** It is a modelling choice, not a description of any host. It makes every solve forecast
slightly less money than may arrive, which can only make the arc shallower and leave more for the
end. It tilts money a little from the weekly prizes toward the ending. Changing it would change
what the solver pays for every host, so it is left alone and recorded in KNOWN_ISSUES.

### Deployed once and linked

**Rule.** `size` is external. A host links one deployed copy rather than compiling its own.

**Why.** It keeps the solver out of each host's bytecode, which keeps the first host's contract
smaller, and lets several games share one copy. The cost is that a host runs whatever code
sits at the address it was linked to, so the address is checked at deployment (see
KNOWN_ISSUES).

### Guards for states the code already rules out

**Rule.** A guard for a state an earlier check already rules out is removed, not kept.

**Why.** The opening payment needs no cap against the pot, because the opening share is checked
at or under the whole pot on the way in. An arc payment needs no cap either, because any growth
factor above flat was accepted only where the forward walk left something over, and that walk
rejects any payment at or above the pot. A guard for a state already ruled out hides which check
actually makes the code safe.

## Related work

Payments that grow at a steady rate until a fund is used up are a growing annuity, a standard
idea in finance. SeasonArc is a growing annuity that re-solves its own growth rate every period
from the live pot and the income just observed, with no one setting it. It is also close to an
amortisation schedule that re-derives itself each period.

Its siblings answer the same question for different endings. BreathEngine holds a floor to a
deadline, Breath sustains a pool with no end date (its closest older relative is the endowment
spending rule, such as Yale's), and SeedGlide spends to zero in equal shares.

## Evidence

Where each claim above is checked.

| Claim | Where |
|-------|-------|
| A collapse gives one step down, then flat payments, with the last payment passed unscaled | `test/StandIn.t.sol` |
| Payments rise; closing over opening at 12, 26, 52 and 104 draws | `test/Ratio.t.sol`, `test/StandIn.t.sol` |
| An arc that flattens pays the last amount rather than falling back | `test/SustainedFallback.t.sol` (`test_whenFlatStillFitsTheArcFlattensRatherThanFallingBack`) |
| The fallback pays more than `pot / drawsLeft`; the $28,744 case | `test/SustainedFallback.t.sol` |
| The fallback pays the largest flat amount the walk survives, and no more | `test/SustainedFallback.t.sol` (`testFuzz_whateverTheFallbackPaysIsTheMostTheWalkSurvives`, return share fuzzed across its whole range) |
| The first-draw and last-draw limits, and the correction search | `test/SustainedFallback.t.sol` (three pinned tests) |
| The formula matches the bisection it replaced | `sim/arc_fuzz.py`, 40,000 seeded random cases, zero difference and zero infeasible answers. This compares the Python formula with a Python bisection; it is not a test of the Solidity, which the fuzz above covers. |
| The old fallback was what made payments fall while the crowd grew | `sim/arc_fuzz.py`, 400 modelled crowd shapes: 59 such draws under `pot / drawsLeft`, all from that branch, and 0 under the rule as it ships |
| The bisection undershot at very large figures | `sim/arc_fuzz.py`, at a pot of 1e30 |
| No draw pays more than the pot, and the last draw empties it, checked after every draw of random seasons | `test/Invariants.t.sol` |
| The two input guards and the zero-draws case | `test/SeasonArc.t.sol` |
