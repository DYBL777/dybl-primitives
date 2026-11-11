# KNOWN_ISSUES: SeasonArc

Limits of the library itself. What a particular host does with it, and that host's own limits,
are in the host's repository.

**A host runs whatever code is at the address it was linked to.** `size` is external and a host
reaches it by DELEGATECALL, which executes the library's code against the host's storage.
SeasonArc is pure and writes nothing, but that is a property of this source, not of the address:
a host linked to the wrong address runs that address's code with its own storage, and a linked
address cannot be changed after deploy. Nothing in the library can guard against it. The check
belongs in the host's deployment, and Lettery TF's deploy script makes it.

**The library's bytes depend on what else is in the compile.** With the settings in
`foundry.toml`, solc 0.8.24 emits 1,310 runtime bytes for the library compiled on its own, and
1,464 when the compile also holds files whose paths sort before `src/`, as forge-std's `lib/`
does. The source and the settings are the same. The main tests import forge-std, so they run the
1,464-byte build; `test-deployable/` runs the 1,310-byte build, and checks that it is that build
(`FOUNDRY_PROFILE=deployable forge test`). A deployment should come from the library built on its
own (`forge build --skip test`), so that a verifier compiling the library from its own source
reproduces the deployed bytes. Every deployed copy of one build has the same code hash
(`test/Link.t.sol`), so a host's deploy can check the linked address against the build it trusts.

**The library trusts the numbers it is given.** It cannot read the host's books, so a pot passed
before its income lands, a return share the host does not actually return, or a last payment
the host did not make produces a confident wrong answer rather than a revert. It refuses the
two inputs it can recognise as malformed: a return share of 10,000 or more, and an opening share
above 10,000. A `lastPaid` of zero is read as the first draw of a season and paid the opening
share. A host can hand the library a zero mid-season three ways: a draw that paid nothing because
the pot was empty, a fallback that sized to nothing, or a last payment scaled by the crowd (as
Lettery TF and BullsTF do) that rounds to zero. The next draw then pays the opening share again.
An opening of 0%, or one that rounds to nothing on a tiny pot, repeats the same way until the
pot can pay (`test/Opening.t.sol`). BullsTF floors its scaled figure at 1 for this reason; a
first-draw flag in the library would remove the case but changes its interface and bytes.

**A collapsing season steps down once.** The solver does not choose a decline: its search for
the growth factor starts at flat. When income falls away the payment holds flat where it can, and
when even a flat payment cannot be carried, the fallback steps it down to the largest flat amount
the pot can carry to the end. Measured in StandIn.t.sol, with the last payment passed unscaled as
the stand-in does: income falling 97% at draw 10 of 52 gives one step down that week and flat
payments after it. A host that scales the last payment by field (Lettery TF does) steps down by
the field ratio and climbs from there, with no flat stretch.

**The cost of a call grows with the draws left.** The solver bisects the growth factor, and each
step walks every remaining draw. Measured through a host in `test/Gas.t.sol`, at 52 draws: on flat
income, 347,818 gas for the dearest call (the second draw, with 51 left) and about 9.6 million
across the season; with the crowd leaving at draw 10, 388,090 for the dearest call (that draw, the
fallback's first) and about 9.0 million across the season. The test fails if the dearest call
passes 450,000 or a season 12 million. A season far longer than 52 draws costs proportionally more
on its early draws, and a host's caller has to be able to afford that.

**An input ceiling exists.** The solver multiplies a payment by a trial growth factor of up to
100 times, so a call reverts on overflow once those products pass the largest number the EVM
holds: in `test/Ceiling.t.sol`, a 52-draw call at a pot of 1e71 answers and the same call at 1e72
reverts. The fallback's formula reverts above a pot of roughly 1.15e73. These are reverts rather
than wrong answers, and far beyond any real amount: 1e71 is 1e65 USDC, or 1e53 of an 18-decimal
token. Between the other tests' bound of 5e14 and a pot of 1e60, `test/Ceiling.t.sol` fuzzes
calls and judges each answer by the rule; between 1e60 and the ceiling, only the pinned call has
been run.
