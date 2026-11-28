# SeasonArc

A Solidity library that decides what each draw of a fixed-length season should pay, from the pot
the game holds now and the number of draws left. Payments rise across the season, and the pot
is spent down by the last draw.

**On Base Sepolia, a test network. Not audited.** One copy of SeasonArc 1.1.6 is deployed there,
its source verified on Basescan, and 23 test contracts from four hosts link it
([On a test network](#on-a-test-network)). The design is the author's, arrived at independently;
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
| Lettery TF 1.4.8-preview | 1.1.6     | `23c0357`                          |
| BullsTF 0.3.16-preview | 1.1.6     | `23c0357`                          |
| SeedTogether 0.84     | 1.1.6     | `23c0357`                          |
| Weather TF 0.2.17     | 1.1.6     | `23c0357`                          |
| SeasonStaking 0.1.0   | 1.1.6     | `23c0357`                          |

1.1.6 changes one comment from 1.1.5 and no code: the instructions are the same, but the metadata
trailer records the source, so a build of 1.1.6 has a different code hash and address from a
build of 1.1.5. A host moving to 1.1.6 deploys and links a new copy; its instructions pin does
not change. A host's documents outside `src/` may differ from this folder's at the same
version; the source is what the table compares.

## On a test network

Base Sepolia (chain 84532), test money only. One copy of SeasonArc 1.1.6 sits at
[`0xDaD8C9Fa842f77151713FD4a8C7BD52330c14Cb1`](https://sepolia.basescan.org/address/0xDaD8C9Fa842f77151713FD4a8C7BD52330c14Cb1#code),
its source verified on Basescan (Exact Match): 1,310 runtime bytes, with the instructions hash in
the table under "Checking a linked copy". Every contract below links that copy: the address is in
each one's code on chain (checked 28 November 2026).

| Host | Contracts | What the runs covered |
|------|-----------|-----------------------|
| Lettery TF | 9 games | a full 52-draw season, an empty draw and refused entries, a 100-ticket draw, a dry run of the mainnet deploy, and two 12-draw seasons at one ticket price, one with 60 newcomers in the closing draw only |
| BullsTF | 9 seasons | seasons of 4 to 24 draws: a draw cancelled under the minimum field and reopened, a stalled game closed by anyone, the keeper's report path, late money against a control, and three 24-draw seasons testing free tickets for loyal players |
| SeedTogether | 3 short seasons and the shipping build | 20-minute draws on Aave's test market: a few large savers, then 500 small ones, then 100 with real Aave rates, an exit from Aave and back, and late money; the shipping build deployed, no draws run |
| Weather TF | 1 season | a 24-draw season, a draw every 30 minutes, opening share 65%: 55 wallets, readings signed and delivered through a Chainlink forwarder with test signers, sealed picks, a thin draw refunded and run again, and late money from draw 16 |

<details>
<summary>Addresses</summary>

| Host | Contract | Address |
|------|----------|---------|
| Lettery TF | game 1 | [`0x03477bab62df1d980f831b39790606a17b2eb5db`](https://sepolia.basescan.org/address/0x03477bab62df1d980f831b39790606a17b2eb5db) |
| Lettery TF | game 2 | [`0x491bf15a0d48fd06e44b3fcb1adb97e64cb0bd4b`](https://sepolia.basescan.org/address/0x491bf15a0d48fd06e44b3fcb1adb97e64cb0bd4b) |
| Lettery TF | game 3 | [`0xf9630825b6ccaa306cb5cd11c2a9e65c98175291`](https://sepolia.basescan.org/address/0xf9630825b6ccaa306cb5cd11c2a9e65c98175291) |
| Lettery TF | game 4 | [`0x84ee2bf4ec8954c26ec03f2ab6202ddcc877b3b4`](https://sepolia.basescan.org/address/0x84ee2bf4ec8954c26ec03f2ab6202ddcc877b3b4) |
| Lettery TF | game 5, the 52-draw season | [`0x84be463042c62d51b18d6c180904256f8b235299`](https://sepolia.basescan.org/address/0x84be463042c62d51b18d6c180904256f8b235299) |
| Lettery TF | game 6 | [`0x471f1070d29f89cf4dae555be9a1c800472fe7e5`](https://sepolia.basescan.org/address/0x471f1070d29f89cf4dae555be9a1c800472fe7e5) |
| Lettery TF | game 7, mainnet dry run | [`0xb5bb5a26bd88dafd66e8015f4ecae9d4c1ae9f9f`](https://sepolia.basescan.org/address/0xb5bb5a26bd88dafd66e8015f4ecae9d4c1ae9f9f) |
| Lettery TF | game 8 | [`0xb196a38d17755ba8ae793c865c81f09e75ffef52`](https://sepolia.basescan.org/address/0xb196a38d17755ba8ae793c865c81f09e75ffef52) |
| Lettery TF | game 9, newcomers in the closing draw | [`0x0bbcec9d2776e7c2d646f66961d2b3a0db4bb7cf`](https://sepolia.basescan.org/address/0x0bbcec9d2776e7c2d646f66961d2b3a0db4bb7cf) |
| BullsTF | season 1 | [`0xcCE03EF2fc52a1dC8b4Ef69eFA0b309AeA6F76F7`](https://sepolia.basescan.org/address/0xcCE03EF2fc52a1dC8b4Ef69eFA0b309AeA6F76F7) |
| BullsTF | season 2 | [`0xd10FFd586deD5f06D012761Bb3983D3348B17158`](https://sepolia.basescan.org/address/0xd10FFd586deD5f06D012761Bb3983D3348B17158) |
| BullsTF | season 3 | [`0x8D8661B8D79B2f3965A442705a92E4b48568F245`](https://sepolia.basescan.org/address/0x8D8661B8D79B2f3965A442705a92E4b48568F245) |
| BullsTF | season 4 | [`0x332509213F0887072D6668A6f1a8C7cB6F2015b6`](https://sepolia.basescan.org/address/0x332509213F0887072D6668A6f1a8C7cB6F2015b6) |
| BullsTF | season 5, control | [`0xB711677D61cFB4d116C07e1Bba1047f00c2dEf59`](https://sepolia.basescan.org/address/0xB711677D61cFB4d116C07e1Bba1047f00c2dEf59) |
| BullsTF | season 6, a test build with two extra entry rules, not in BullsTF's repository | [`0x8C0E6Ce55431B7cB90d8d3D875B7a3511a82Ee4A`](https://sepolia.basescan.org/address/0x8C0E6Ce55431B7cB90d8d3D875B7a3511a82Ee4A) |
| BullsTF | season 7, a test build with free tickets for loyal players, not in BullsTF's repository | [`0x506f0E20Edd862718c0462b3C59a1B834e5d3442`](https://sepolia.basescan.org/address/0x506f0E20Edd862718c0462b3C59a1B834e5d3442) |
| BullsTF | season 8, a test build with free tickets for loyal players, not in BullsTF's repository | [`0xbD7ACa502981B4CF2D97e6B8fE587603057223cc`](https://sepolia.basescan.org/address/0xbD7ACa502981B4CF2D97e6B8fE587603057223cc) |
| BullsTF | season 9, a test build with free tickets for loyal players, not in BullsTF's repository | [`0x2D9785a30D7AD69300A8ce1171B0eD01C1FD465b`](https://sepolia.basescan.org/address/0x2D9785a30D7AD69300A8ce1171B0eD01C1FD465b) |
| Weather TF | season 1 | [`0x1A40A56e8289291215AD878ce86081Cb40005471`](https://sepolia.basescan.org/address/0x1A40A56e8289291215AD878ce86081Cb40005471) |
| SeedTogether | season 1 | [`0x3aba83f7c795601fb2e7b8e80f4d04fc0d79c210`](https://sepolia.basescan.org/address/0x3aba83f7c795601fb2e7b8e80f4d04fc0d79c210) |
| SeedTogether | season 2 | [`0xe38a25627bc77784db67dca113aedcfc4c80835a`](https://sepolia.basescan.org/address/0xe38a25627bc77784db67dca113aedcfc4c80835a) |
| SeedTogether | season 3 | [`0x46decba3d45f9297df8006b2791125bf529470c4`](https://sepolia.basescan.org/address/0x46decba3d45f9297df8006b2791125bf529470c4) |
| SeedTogether | shipping build | [`0x11864d64f514768937a7e50b2c87f16d96520fc0`](https://sepolia.basescan.org/address/0x11864d64f514768937a7e50b2c87f16d96520fc0) |

</details>

What the runs showed for SeasonArc.

From Lettery TF, the host SeasonArc was written for. Its late-entry price, treasury split and
end-of-season share per ticket are its own, not SeasonArc's:

- **A full 52-draw season.** Game 5 (draws 20 minutes apart, a $5 ticket, a 25% opening, 28
  scripted wallets and one person buying through the play page) resolved all 52 draws on
  Chainlink VRF. The keeper was offline for about 5 hours; the missed slot moved the game to the
  next one and the draw numbers stayed in sequence. After the season the contract held
  $1,175.000789 against $1,175.000788 owed.
- **The closing draw takes the pot.** In games 8 and 9 (12 draws at one $5 price, no late-entry
  price) the closing draw was sized to the whole pot and left it at zero: $29.95 in game 8, and
  $1,003.44 in game 9, where the pot had been between $132 and $954 before it.
- **Money arriving only for the closing draw.** In game 9, 40 wallets bought a ticket in every
  draw (480 tickets) and 60 new wallets bought one ticket each in the closing draw only (60
  tickets). With no late-entry rule, the 60 held 11% of the tickets and took 35% of what was
  paid out: $760.81 back on $300, against $1,399.19 back on $2,400 for the 40 who stayed. Two of
  the 60 won about $350 each. This is one run; it is the case KNOWN_ISSUES describes, and what a
  host's own entry rules are for.

From BullsTF's seasons:

- **The last draw paid the most.** In the 24-draw season 3 it paid $211.63 against $152.09 the
  draw before, and in the 12-draw season 4 $12.21 against $8.27.
- **It sizes on the field each draw has.** In season 4 a draw's total fell twice, both times when
  fewer tickets were bought, while the amount paid per ticket rose every draw, from $0.025 to
  $0.22.
- **The pot was paid out.** Each season that reached its last draw ended with the contract holding
  only rounding once every winner had claimed.
- **Free tickets for loyal players, on a test build.** Seasons 7 to 9 (24 draws, a $0.10 ticket,
  openings of 35%, 35% and 50%) ran a modified copy kept outside the repository, giving a free
  ticket to wallets that keep playing. Late money (wallets that bought only from draw 17) got back
  $0.74, $0.66 and $0.49 per $1 over the season, against $1.28, $1.54 and $1.48 for loyal wallets
  in the same late draws. When the late money stopped before the last three draws of season 9, paid
  tickets fell from 364 to 114 and the prize per paid ticket kept rising, from $0.093 to $0.168.
  Three seasons with scripted players are one run each: the direction is the finding, not the
  figures.


From Weather TF's 24-draw season (a draw every 30 minutes, an opening share of 65%, a $5 ticket,
53 scripted wallets and two people buying through the play page). Its tiers, sealed picks and
readings are its own, not SeasonArc's:

- **A high opening, and a draw total that rose every draw.** All 24 draws resolved on Base
  Sepolia. The three tiers together paid $121.68 in draw 1 and $405.54 in the last, 3.3 times as
  much, and the total was higher each draw than the one before. Even the smallest prize paid
  $11.83 in draw 1 (2.4 times the ticket) and $39.43 in the last (7.9 times).
- **A thin draw was refunded and run again.** One draw had 20 tickets, under the minimum of 34:
  every ticket was credited back and the draw reopened at the next slot.
- **The season ended empty.** After the last winner withdrew the contract held nothing. Players
  won $5,364.00 of $6,705 played (80%), and the treasury's $1,341.00 went to the beneficiary.
- **Late money.** Three wallets that began buying at draw 16 spent $675 and won $660 ($0.98 per
  $1); the 40 wallets that played every draw got $0.75 per $1. With random picks and this few
  tickets, luck is a large part of that. It is one run.

From SeedTogether's three 12-draw seasons, where SeasonArc sizes each draw from the interest on
the savers' deposits. SeedTogether's reserve, and its rule that tops a draw up from the reserve to
the last prize per ticket, are its own, not SeasonArc's:

- **Prizes rose to a closing draw that emptied the pot.** In season 1 (21 savers of about
  $100,000) the prize total rose every draw, from $1,440.61 to $19,513.02, and in season 2 (500
  savers of about $1,100, with new money arriving twice) from $652.49 to $3,726.68. In both, the
  closing draw left the pot and the reserve at zero.
- **A sudden fall was sized from before the fall.** A minute before season 1's draw 5, savers
  holding $400,000 (20%) withdrew. The draw paid $2,614.80, against $2,571.14 the draw before.
- **When the interest stopped, SeasonArc stepped down.** In season 3 (100 savers, Aave's real
  monthly rates from December 2025 to November 2026) the money left Aave for two draws. SeasonArc
  sized draw 4 at $58.90; SeedTogether's reserve paid it at $75.42, the same as draw 3, and draw 5
  paid $74.04 (1.8% less) as the reserve ran out. From draw 6 every draw paid more than the one
  before, to $1,238.86 at the close.
- **Late money took a small share.** $100,000, more than every other saver together, arrived
  19 minutes before season 3's closing draw. Weighted by money and time held (SeedTogether 0.84's
  rule), it held 8.2% of the odds and won $152.95, against about $858 its money earned in that
  time.

The draws, settlement transactions and snags for each host are in that host's own
`SEPOLIA_TESTS.md`; those repositories are private for now. SeasonStaking carries the same source and has not run
on a test network yet.

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
