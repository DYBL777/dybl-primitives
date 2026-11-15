# SeasonArc

A Solidity library that decides what each draw of a fixed-length season should pay, from the pot
the game holds now and the number of draws left. Payments rise across the season, and the pot
is spent down by the last draw.

**Pre-testnet. Not deployed, not audited.** The design is the author's, arrived at independently;
how it sits beside related work is in [DESIGN.md](DESIGN.md#related-work). AI was the researcher,
the economic modeller and the co-developer: writing the Solidity, each step tested and reviewed
before the next began. What is unproven or carried as a known limit is in
[KNOWN_ISSUES.md](KNOWN_ISSUES.md).

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

Why each rule is shaped as it is, what it replaced, and where each claim is tested are in
[DESIGN.md](DESIGN.md).

## What a season looks like

Measured through the library, not modelled:

    flat income, 52 draws        opening 10,000, closing 164,194: a rise of about 16.4x
                                 (StandIn.t.sol)
    closing over opening         about 14x at 12 draws, 15.7x at 26, 16.4x at 52,
                                 16.8x at 104 (Ratio.t.sol, same inputs at every length)
    income falls 97% at draw 10  one step down that week, then flat to the end; no draw pays
                                 nothing and the pot still ends empty (StandIn.t.sol)

The collapse shape is with the last payment passed unscaled, as the stand-in does. A host that
scales it by the change in field (Lettery TF does) steps down by the field ratio and climbs from
there.

All of these run at a 29.9% return share, which assumes the jackpot is missed every draw and the
other tiers pay out. A won jackpot returns less to the pot; a tier that finds no winner and
returns its pool returns more. So these are the library's figures at one assumption, not a floor
or a ceiling on what a real host pays.

## Using it

**`size` is external, so a host links to one deployed copy** rather than carrying the solver in
its own bytecode. Foundry deploys an unlinked library through the standard deterministic
deployer, so the library's address follows from its exact bytecode. That bytecode ends with a
hash of the build's metadata, which records source paths and remappings, so the address belongs
to the build that deployed it: a host that wants an existing copy links that copy's address
rather than rebuilding it.

**A host reaches it by DELEGATECALL**, which runs the library's code with the host's storage.
SeasonArc is pure and touches no storage, but a host runs whatever code sits at the address it
was linked to. A host's deploy should check the code at that address before it matters, against
the instructions hash below. Lettery TF's deploy script is the worked example.

**Checking a linked copy.** Compare the library's instructions, not its whole code. The last
bytes of the runtime code are the compiler's metadata trailer, which differs from one tree to
the next (paths, remappings, forge version), so two correct copies can have different code
hashes and addresses. The instructions are the same. To compute: the last two bytes of the
runtime code give the trailer's length; drop that many bytes plus two, then take the keccak256.
SeasonArc has no call-protection placeholder, so the code on chain is the compiled code.

| SeasonArc      | Runtime bytes | Instructions hash (trailer left off)                                 |
|----------------|---------------|----------------------------------------------------------------------|
| 1.1.5, 1.1.6   | 1,310         | `0xc4f7e21e0da4c59421372ffc0770135c73369dd7d2498c115b6a0281c0b6b2fb` |

The value holds for the settings in `foundry.toml` (paris, via-IR, optimizer at 1 run) and the
library built on its own. Other settings, the optimizer's above all, give other instructions,
and a host's deploy should refuse them. A release that changes only comments or tests keeps the
value; `test-deployable/` fails until a release that changes the code publishes a new one.

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
author's words, is in [ORIGIN.md](https://github.com/DYBL777/dybl-primitives/blob/main/ORIGIN.md)
at the root of the DYBL primitives repository.

Each host carries a copy of this folder and links the library unedited. Which copy each carries:

| Host                  | SeasonArc | `src/SeasonArc.sol` matches commit |
|-----------------------|-----------|------------------------------------|
| Lettery TF 1.4.7      | 1.1.6     | `23c0357`                          |
| BullsTF 0.3.8         | 1.1.6     | `23c0357`                          |
| SeedTogether 0.78     | 1.1.6     | `23c0357`                          |

1.1.6 changes one comment from 1.1.5 and no code: the instructions are the same, but the metadata
trailer records the source, so a build of 1.1.6 has a different code hash and address from a
build of 1.1.5. A host moving to 1.1.6 deploys and links a new copy; its instructions pin does
not change. A host's documents outside `src/` may differ from this folder's at the same
version; the source is what the table compares.

## Season Lab

[SeasonArc Lab](https://claude.ai/artifact/T8ZudBcJVCNyQrKA7FfLjW) (`lab/index.html`) runs whole
seasons through the library for each host as shipped: pick a host, shape the crowd (flat,
growing, shrinking, a crash or a surge mid-season), and see each draw's size, the rule that sized
it, and what it comes to per player. It also draws the same season with the last payment passed
back under the other hosts' rules, puts the three hosts on one scale, and answers single calls.

Its draws are sized by `lab/seasonarc.js`, a line-for-line port of the library in whole numbers,
with the library's rounding and reverts. `lab/vectors.json` holds 1,566 calls with the library's
answers: `test/Vectors.t.sol` checks the compiled library against every one, and
`node lab/seasonarc.js check` checks the port, so the two are held to one file. A host page that
needs the library's rule can load the port, or check its own copy against the file, instead of
porting it again.

Each host is cut down to the money the library sees, and checked against the host's own model:
BullsTF and SeedTogether to the unit on every draw but the closing one across five crowd shapes,
and Lettery TF the same on steady crowds. The page lists what each host is reduced to and what it
leaves out; each host's own Season Lab has its full money.

## Files

    src/SeasonArc.sol                 the library
    DESIGN.md                         why each rule is shaped as it is, and the evidence for it
    test/SeasonArc.t.sol              mostly single calls against figures worked out by hand
    test/SustainedFallback.t.sol      the flat-payment fallback, against the rule it replaced
    test/Ratio.t.sol                  closing over opening at 12, 26, 52 and 104 draws
    test/Sim.t.sol                    whole seasons called directly
    test/StandInGame.sol              the smallest game that can run a season on the library
    test/StandIn.t.sol                whole seasons through that game, including a fuzzed one
    test/Invariants.t.sol             random runs of seasons, crowds and income, rules checked every draw
    test/Exhaustive.t.sol             every call on seven grids of 40,000, against the rule coded apart
    test/Link.t.sol                   the code hash of a build, and a host linked to an empty address
    test/Proofs.t.sol                 symbolic proofs of the edges of size, run with Halmos
    test/Ceiling.t.sol                very large figures, and where the arithmetic stops
    test/Gas.t.sol                    what a call and a season cost
    test/ArcRule.sol                  the rule coded apart from the library, used to judge answers
    test/Vectors.t.sol                the library against every case in lab/vectors.json
    test-deployable/                  the build that deploys, tested on its own, and its instructions hash
    sim/arc_fuzz.py                   the rule reimplemented in Python across random seasons
    lab/index.html                    the Season Lab
    lab/seasonarc.js                  the library ported to JavaScript, as the lab runs it
    lab/vectors.json                  1,566 calls and the library's answers

From this folder, on a fresh clone:

    forge install foundry-rs/forge-std@v1.16.2
    forge test
    FOUNDRY_PROFILE=deployable forge test
    python3 sim/arc_fuzz.py
    node lab/seasonarc.js check
    halmos --contract SeasonArcProofs

On forge 1.5.1 with solc 0.8.24: 71 tests across 12 suites, and 9 more in `test-deployable/`,
zero failures. On Halmos 0.3.3: five proofs, all passing.

**The library's size depends on what is compiled with it.** With the settings in `foundry.toml`
(its first host's), the same source builds to 1,310 runtime bytes when the library is compiled
on its own (`forge build --skip test`) and to 1,464 when the test files are compiled with it
(`forge build`). Run the first on a clean build (`forge clean` before it): straight after
`forge test`, forge reuses the output it has cached and reports 1,464. The settings are identical; files that sort before `src/` in the same compile,
as forge-std's `lib/` does, change the code the compiler emits. This is also the likely cause of the gap seen at 1.0.0 (1,278 here,
1,432 in the host), which was not explained at the time. The address of a deployed copy follows
from the bytes of the build that deployed it, which is why a host links the copy it deployed
rather than a rebuild. What this means for a deployment is in KNOWN_ISSUES.

## Licence

Business Source License 1.1, with the same terms as Lettery TF: non-production use is granted,
and it becomes MIT on 1 February 2030. See [LICENSE](LICENSE). The test tree and the Python sim
are MIT.
