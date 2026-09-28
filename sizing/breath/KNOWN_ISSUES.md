# KNOWN_ISSUES: Breath

Limits of the library itself. What a particular host does with it, and that host's own limits,
are in the host's repository.

**The dust guard can cut a payout below the fall rail.** A draw whose railed amount lands under
minDraw pays nothing, even where the fall rail alone would have allowed a payment. In a test, a
last payment 5% above minDraw followed by an income collapse pays zero where the rail allowed 94%
of it. The fall rail holds in every other case except the pot running short. A host that wants the
rail to hold at every size sets minDraw to zero, and then handles zero-amount draws itself.
`test/Rails.t.sol` pins this.

**The minDraw ceiling assumes a six-decimal token.** validate() refuses a minDraw above 10_000e6,
which is ten thousand whole tokens at six decimals. On an 18-decimal asset the same ceiling is a
hundred-millionth of a token, so any guard a host could set is dust and the guard is effectively
off. A host on another decimal count needs a different ceiling.

**coverTarget and spareShareBps are required even by a host that never calls spare().** validate()
refuses a zero coverTarget and a spareShareBps outside (0, 10,000), so a host sizing its own extra
payouts, as the first host does, still has to supply values that do nothing.

**The library trusts the numbers it is given.** It cannot read the host's books. Breakeven grosses
income up by rhoBps, the share of a prize that comes back to the pot, so a host that passes a
share it does not actually return gets a confident wrong answer rather than a revert. The library
refuses the one value it can recognise as malformed: a rhoBps of 10,000 or more. The first host
measures rhoBps from its observed miss rate rather than assuming it.

**The pot's size is left to the host.** Payouts are anchored to income and yield, not to the pot.
With pace set below 100% of breakeven, as in the test fixture, the pot keeps growing on a flat
book and the yield it earns raises breakeven further. Taking the top off is the host's decision,
through spare() or its own rule.

**Call order is the host's responsibility.** observe() is called once per draw from one site;
calling it twice weights that draw double. commit() records only the regular weekly prize. A
boost or any other extra payout committed there would become the next draw's starting point, and
the fall rail would then hold the prize up after the extra payment had passed.

**Each host compiles its own copy.** Every function is internal, so the library is compiled into
each host rather than deployed once and linked. Two hosts built with different compiler settings
carry different bytecode for the same source.

**Coverage.** 25 library-level tests through a stand-in host. Mutation-checked: twelve deliberate
breaks to the library, plus a reordering of the payout steps, each fail at least one of the first
20. The other 5 are invariants, checked after every draw while a minimal game runs random
sequences of draws, droughts and surges: no payout exceeds the pot, no dust is paid, both rails
hold and every unit is accounted for. Removing the rise rail, the fall rail, the pot cap or the
dust guard each fails them. Not audited. Not deployed.
