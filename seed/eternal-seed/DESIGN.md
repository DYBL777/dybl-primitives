# EternalSeed: design

The thinking behind the seed rule: what it is, the two ways of holding money back, the four
ways a season can end, and where each game sits. The rule itself, and the traps an integrator
needs, are in `src/EternalSeed.sol`.

## What "Eternal" means

Eternal describes the pot, not an amount. The name came from the growth: a
lottery that keeps a share back every week starts the next week above zero, so
the pot compounds instead of resetting. It was never a claim that some balance
sits untouchable forever. Whether a pot can literally be eternal is a question
the hosts answer differently, and one of them answers no. See Endings, below.

## Two axes

Earlier versions of the library's header listed seventeen numbered variants. Most were one
mechanism at a different setting, and the numbering collided with a superseded
reference repository that used the same numbers for different mechanisms. The
design space is described better by two independent questions.

RETENTION asks how money is held back. Two answers: Floor and Flow.
ENDING asks what the held-back money is for and where it finishes. Four answers:
Compound, Port, Spend-down and Return.

Any retention rule can carry any ending. The suite has moved along the ending
axis while retention stood still, which is why the old list kept filing endings
as retention variants and never sat right.

## Retention: Floor (formulation A)

A fraction of the pot cannot be distributed while the game or season runs. It
stays in the pot, earning yield where the host supplies it to a lender, and is
released through the host's defined exits. This was the first form of the idea.
Functions: maxDistributable(), seedFloor().

CEILING POLICY. The ceiling maxPayoutBps may be fixed at deployment, adjustable
by an owner within a committed maximum, or scheduled to rise over time. Each
changes who may move the ceiling and how fast; none changes the mechanism.

## Retention: Flow (formulation B)

A share of each prize returns to the pot instead of being paid out, so the pot
compounds period on period. The seed here is not a floor; it is an engine.
Functions: seedReturn(), distributable().

RATE POLICY. The returning share seedBps may be fixed, adjustable under a
timelock, scheduled to fall or rise across a season, gated on participation,
set per prize tier, or suspended once the pot reaches a ceiling. Each is the
same mechanism on a different schedule.

WHAT ACTUALLY RETURNS. seedBps is not the whole of it. When a top prize goes
unwon, some of that prize also comes back to the pot, so the true returning
share is the reseed plus the routed part of missed prizes. Measuring it from
money flows misleads, because a rolled jackpot looks permanently retained until
somebody wins it; counting how often prizes are missed does not. Two host shapes
call for two answers, and both are correct.

- A perpetual host has no end date to re-anchor against, so it measures the
  miss rate as it runs. Lettery Perpetual does this in its own code, where the
  returning share is reseed + jackpotShare * missToPot * missRate.
- A season host knows its routing at deployment and sizes every draw from the
  pot it actually holds, so it can compute the share once, at the miss-always
  limit, and any error does not carry forward. In Lettery TF this is RETURN_BPS:
  the 20% reseed withheld from every prize, plus 30% of the jackpot tier's share
  of a prize when the jackpot is missed. At the shipped split that is 20 points
  plus 9.9 points, 29.9% in all. It leaves out money a draw returns on its own:
  a bottom tier nobody wins, a tier too thin to pay and rounding dust all go
  back to the pot, so the forecast sits on the low side.

## Endings: what the seed is for

COMPOUND. The pot has no end date, so the seed's job is to keep it growing and
the payout rule must be affordable indefinitely. Lettery Perpetual.

PORT. What accumulates in one season becomes the opening position of the next,
so a season's players are funding the next season rather than losing their
contribution at the close. Specified, not yet built.

SPEND-DOWN. The pot is aimed at zero by a known last draw, with the largest
payments near the end. SeedTogether, which sizes each draw with SeasonArc and
holds a share of each draw back in a reserve that is paid out by the last draw.

RETURN. The season ends on a known draw, and what the season did not pay out as
prizes is handed back to those who funded it: per ticket in Lettery TF, by
seniority in BullsEthCRE. BullsEthCRE's order is the investor's unreleased seed
first, then committed players up to their promised return, with anything above
that going to the treasury (all of it, if no committed player qualifies). Its
sizing solver holds the pot above that obligation to the last draw, and the last
draw pays out everything above it.

BALLAST. In the Spend-down and Return rows the seed's job changes. It is not
growing the pot toward an open future; it is holding the shape of a pot being
spent on purpose, so that the season reaches its last draws with the largest
payments still ahead of it. The sizing solver treats the returning share as
known and aims through it (SeasonArc's returnBps input).

THREE ANSWERS TO "ETERNAL". Lettery Perpetual never ends, so its pot is eternal
in the plain sense. The port carries a pot across a boundary, so it is eternal
by becoming the next one. SeedTogether and Lettery TF end on a date and hand the
pot back, which is not eternal at all, deliberately. The name came from the
first idea; the hosts are where it was tested.

## The grid

Retention across, ending down. Each cell names the host that runs it, or says
why it is empty.

|                | Floor             | Flow                        |
|----------------|-------------------|-----------------------------|
| **Compound**   | the original idea | Lettery Perpetual           |
| **Port**       | open              | specified, see Compositions |
| **Spend-down** | open, see below   | SeedTogether                |
| **Return**     | open              | Lettery TF, BullsEthCRE     |

Floor with Spend-down has no known implementation: a protected minimum that is
itself scheduled to be spent into a finale, so that even the untouchable part of
the pot carries a maturity date. It is recorded because a taxonomy that predicts
an unbuilt cell is doing its job. Whether it is a product or a curiosity is open.

## Compositions

Retention rules combine. Four combinations:

FLOOR PLUS FLOW. A floor with a flow above it. The pot does not fall below the
floor, and also compounds each draw above it.

FLOW TO FLOOR. A flow that converts to a floor at a trigger, for example the
midpoint of a season. Compounding first, protection after.

SEASONAL INHERITANCE. A flow in one season that becomes the protected floor of
the next. The Port ending expressed as a composition. The grid files it under
Flow because that is the rule running while the season does; it lands as a
Floor in the season after.

DUAL FLOOR. Two floors for two classes of capital, a player floor and an investor
floor. Meaningful only where more than one class of money is in the pot; with one
class it collapses to an ordinary floor. Specified, not built here.

ADJACENT: YIELD-FUNDED SEED. Principal is not locked. The seed is funded only
from diverted yield, so deposits stay withdrawable: under stress more yield
routes to the seed, under stability the seed's yield routes to long-standing
participants. It sits outside both retention rules because neither a floor on
the pot nor a share of each prize is involved, only yield. It differs from a
floor that earns yield: that is a floor which earns, this is a seed made of
earnings. Specified, not built.

## Sizing solvers

Every seed needs an answer to a separate question: what does this period pay?
That question is automatic distribution, answered by the sizing solvers in
[../../sizing](../../sizing). Two are in this repository, each for a different
ending condition:

- Sustain with no end: Breath.sol, first host Lettery Perpetual.
- Spend down on a rising arc: SeasonArc.sol, first host Lettery TF.

A third, which holds a floor to a deadline, stays inside BullsEthCRE.

Lettery TF sits in the grid's Return row: the arc spends its prize pot down, and
what the seed held back is handed back per ticket at the close.

For a game that spends its pot down by a date, where its prize money comes from
decides how large the first payment must be. A pot funded by yield on parked
deposits can open small, because nobody paid an entry price that the payment has
to justify. A pot funded by ticket sales cannot: the smallest prize is meant to be
worth more than the ticket from the first draw. SeasonArc takes the opening share
as an input, so both kinds run on it: SeedTogether on yield, Lettery TF on
tickets.

## Lineage

The question was how to make the pot bigger. The first answer was to keep part
of it back, a floor that was never paid out. Then a share of every prize coming
home, so the pot grew draw on draw. Then putting the money held back to work,
earning while it waited and drawn back when needed. Held back as a floor or
returned as a share of each prize, how large the pot gets is set by income, yield
and what each draw pays. Either way the pot can become large, and most of what
followed answers the question that raised: what should a large pot actually do.
The sizing solvers, the endings and the protections all come from there. The
mechanism barely changed; what it was for did.
