# KNOWN_ISSUES: SeasonArc

Limits of the library itself. What a particular host does with it, and that host's own limits,
are in the host's repository.

**A host runs whatever code is at the address it was linked to.** `size` is external and a host
reaches it by DELEGATECALL, which executes the library's code against the host's storage.
SeasonArc is pure and writes nothing, but that is a property of this source, not of the address:
a host linked to the wrong address runs that address's code with its own storage, and a linked
address cannot be changed after deploy. Nothing in the library can guard against it. The check
belongs in the host's deployment, and Lettery TF's deploy script makes it.

**The library trusts the numbers it is given.** It cannot read the host's books, so a pot passed
before its income lands, a return share the host does not actually return, or a last payment
the host did not make produces a confident wrong answer rather than a revert. It refuses the
two inputs it can recognise as malformed: a return share of 10,000 or more, and an opening share
above 10,000. A `lastPaid` of zero is read as the first draw of a season and paid the opening
share, so a host that scales the last payment (Lettery TF scales it by the change in field) can
reach that branch mid-season if the scaled figure rounds to zero.

**The solve under-counts the pot by one draw's returned share.** The forward walk takes no
returned share back on the last remaining draw. A host that withholds on its last draw too has
that money, and the solver does not count it. The direction is conservative: less forecast money
means a shallower arc, which errs toward leaving money for the last draw rather than toward
paying more than the season can carry. It tilts money from the draws before the end toward the
end, and is a modelling choice rather than an accident; the comment in `_leftover` says so.

**A collapsing season steps down once.** The solver does not choose a decline: its search for
the growth factor starts at flat. When income falls away the payment holds flat where it can, and
when even a flat payment cannot be carried, the fallback steps it down to the largest flat amount
the pot can carry to the end. Measured in StandIn.t.sol, with the last payment passed unscaled as
the stand-in does: income falling 97% at draw 10 of 52 gives one step down that week and flat
payments after it. A host that scales the last payment by field (Lettery TF does) steps down by
the field ratio and climbs from there, with no flat stretch.

**The cost of a call grows with the draws left.** The solver bisects the growth factor, and each
step walks every remaining draw. Measured at 52 draws on flat income, with a harness not in this
repository and asserted by no test: about 347,000 gas for the dearest call (the second draw, with
51 left) and about 9.6 million across the season. A season
far longer than 52 draws costs proportionally more on its early draws, and a host's caller has
to be able to afford that.

**An input ceiling exists and is unexplored.** The fallback's arithmetic reverts on overflow
above a pot of roughly 1.15e73. That is a revert rather than a wrong answer and far beyond any
figure a six-decimal token can hold, but the fuzz of the fallback (`test/SustainedFallback.t.sol`)
bounds the pot at 5e14, so nothing between the two has been exercised.
