# SeasonArc

A Solidity library that decides what each draw of a fixed-length season should pay, from the pot
the game holds now and the number of draws left. Payments rise across the season, and the pot
is spent down by the last draw.

**Pre-testnet. Not deployed, not audited.** The design and the maths are the author's; the
Solidity was written with AI assistance under that direction. What is unproven or carried as a
known limit is in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## What it answers

    size(pot, lastPaid, drawsLeft, incomeEstimate, returnBps, openingBps)
        returns (amount, bind)

    pot             the prize pot, after this draw's income has landed
    lastPaid        what the previous draw paid; zero on the first draw
    drawsLeft       draws remaining, including this one; one means the last draw
    incomeEstimate  the income the solver assumes arrives on each remaining draw
    returnBps       the share of each payment that comes back to the pot (under 10,000)
    openingBps      the share of the pot the first draw pays (at most 10,000)

    amount          what this draw should pay
    bind            which rule decided it: OPENING, ARC, SUSTAINED, POT or CLOSING

## The rule, in plain words

- **The first draw** pays a fixed share of the pot. That share is the season's only dial: a
  larger opening means a larger first prize and a shallower climb after it.
- **Every draw after that** pays the last payment times a growth factor, and the factor is
  solved fresh each draw so that carrying on at that growth spends the pot by the last draw. The
  solver assumes the income it was just shown keeps arriving and that `returnBps` of every
  payment comes back. Nothing is forecast beyond that, so a crowd that grows or shrinks is
  absorbed on the next draw rather than breaking a plan made at the start.
- **If even flat payments would run the pot dry**, it pays the largest flat amount the pot and
  its future income can carry to the end instead.
- **The last draw** pays the whole pot. **An empty pot** pays nothing.

The reasoning behind each branch, including the ones that were tried and removed, is in the
comments of [src/SeasonArc.sol](src/SeasonArc.sol).

## What a season looks like

Measured through the library, not modelled:

    flat income, 52 draws        opening 10,000, closing 164,194: a rise of about 16.4x
    closing over opening         about 14x at 12 draws, 15.7x at 26, 16.4x at 52,
                                 16.8x at 104 (Ratio.t.sol, same inputs at every length)
    income falls 97% at draw 10  one step down that week, then flat to the end; no draw pays
                                 nothing and the pot still ends empty (StandIn.t.sol)

Those are the library's own figures with every payment's returned share coming back. A real
host lifts the closing draw further, because tiers that find no winner return their money to
the pot.

## Using it

**`size` is external, so a host links to one deployed copy** rather than carrying the solver in
its own bytecode. Foundry deploys an unlinked library through the standard deterministic
deployer, so the library's address follows from its exact bytecode. That bytecode carries a
hash of the build's metadata, source path included, so the address belongs to the build that
deployed it: a host that wants an existing copy links that copy's address rather than
rebuilding it.

**A host reaches it by DELEGATECALL**, which runs the library's code with the host's storage.
SeasonArc is pure and touches no storage, but a host runs whatever code sits at the address it
was linked to. A host's deploy should check that address before it matters; Lettery TF's deploy
script does, and is the worked example.

**What the host is trusted to pass.** The library cannot see the host's books. It sizes from
the numbers it is given, so a host that passes the pot before its income lands, or a return
share it does not actually return, gets a confident wrong answer. The library refuses the two
inputs it can recognise as wrong: a return share of 10,000 or more, and an opening share above
10,000.

**What it does not do.** It knows nothing of tickets, tiers, winners or withholding. It returns
an amount; the host decides how that amount is split and paid.

## Hosts

**Lettery TF**, a weekly lottery with a fixed season, is the host this library was written for
and the first to link it. Its history before it was extracted, every change to the solver
included, is in Lettery TF's CHANGELOG. Where the seed and the breath behind it came from, in the
author's words, is in [ORIGIN.md](../../ORIGIN.md) at the root of the DYBL primitives repository.

## Files

    src/SeasonArc.sol                 the library
    test/SeasonArc.t.sol              single calls against figures worked out by hand
    test/SustainedFallback.t.sol      the flat-payment fallback, against the rule it replaced
    test/Ratio.t.sol                  closing over opening at 12, 26, 52 and 104 draws
    test/Sim.t.sol                    whole seasons called directly
    test/StandInGame.sol              the smallest game that can run a season on the library
    test/StandIn.t.sol                whole seasons through that game, including a fuzzed one
    test/Invariants.t.sol             random runs of seasons, crowds and income, rules checked every draw
    sim/arc_fuzz.py                   the rule reimplemented in Python across random seasons

From this folder, on a fresh clone:

    forge install foundry-rs/forge-std@v1.16.2
    forge test
    python3 sim/arc_fuzz.py

On forge 1.5.1 with solc 0.8.24: 32 tests across 6 suites, zero failures. The library builds to
1,310 runtime bytes with the settings in `foundry.toml`, which are the settings of its first
host, and measured the same inside that host. At 1.0.0 the two builds differed with identical
settings (1,278 here, 1,432 in the host). The cause was not traced, the likely one being that
viaIR output depends on what else is compiled alongside, and it is one more reason a host links
the copy it deployed rather than a rebuild.

## Licence

Business Source License 1.1, with the same terms as Lettery TF: non-production use is granted,
and it becomes MIT on 1 February 2030. See [LICENSE](LICENSE). The test tree is MIT.
