# DYBL primitives

Protect it, grow it, pace it.

Solidity libraries for games and savings products that hold a pot of money. One question runs
through all of them: how to make the pot bigger, and then what a big pot should do. The seed
decides how much of the pot is kept back; the sizing solvers decide what each draw pays.

**Pre-testnet. Not deployed, not audited.** Each library's known limits are in its own
KNOWN_ISSUES.md.

Where the ideas came from is in [ORIGIN.md](ORIGIN.md). The library names are working names,
open to change. Earlier posts called EternalSeed the Compounding Reserve and BreathEngine the
Solvency Autopilot.

| Library     | Folder                                        | Answers                                  | First host        |
|-------------|-----------------------------------------------|------------------------------------------|-------------------|
| EternalSeed | [seed/eternal-seed](seed/eternal-seed)        | how much of the pot is kept back          | written into each game, not imported |
| BreathEngine | [sizing/breath-engine](sizing/breath-engine)  | reach a floor by a deadline               | BullsEthCRE       |
| Breath      | [sizing/breath](sizing/breath)                | what a game with no end date can afford   | Lettery Perpetual |
| SeasonArc   | [sizing/season-arc](sizing/season-arc)        | a rising arc to the last draw             | Lettery TF        |
| SeedGlide   | sizing/seed-glide (to come)                   | equal shares down to zero                 | SeedTogether      |

Each folder is its own Foundry project, built with the same compiler settings as its first host,
so the library tested here is the one that host carries. To test one:

    cd sizing/breath
    forge install foundry-rs/forge-std@v1.16.2
    forge test

## Design decisions

**What the libraries trust.** None of them reads prices or any outside feed. Each is handed
figures its game already holds: the pot, the net income from tickets sold, the yield its lender
has credited, and, for Breath, the share of prizes that came back to the pot, which its first
game measures from its own missed jackpots. A wrong figure gives a confident wrong answer rather
than an error, so checking inputs is the game's job. Raising the income or yield a library sees
means putting real money into the pot. Breath also limits how far a payout can rise in one draw;
the others size against the pot as the game reports it. Whether a game's own inputs can be
gamed, for example by a large purchase or deposit just before a draw, belongs to that game's
own review.

**Where Chainlink fits.** The libraries need no oracle, which keeps outside data out of the
maths. The games around them do need outside services, and for those we use and recommend
Chainlink: the lottery games draw winners with Chainlink VRF, and BullsEthCRE runs on Chainlink
CRE with Chainlink price feeds.

**Compiled in, or deployed once.** All four libraries are written to be reused; they differ in
how a game uses them. EternalSeed, Breath and BreathEngine are internal: each game compiles its
own copy, which costs no outside call and needs no trusted address. SeasonArc is external: it is
deployed once and linked, to keep its first game's contract smaller. A linked game runs whatever
code sits at the address it was linked to, so that address is checked at deployment. Breath
could be linked the same way if a game needs the space.

**How the code was checked.** The Solidity was written with AI assistance, so the tests are the
evidence. Tests are named for the claims they check; deliberate breaks to each library were used
to show the tests catch them; Breath compiles to the same code as its first game's copy; and
BreathEngine's answers match its first game's solver across fuzzed inputs, except at one
documented boundary. EternalSeed's tests also check each game's own seed line against it.

**Beyond single calls.** Every library here has an invariant suite: Foundry drives random
sequences of draws, droughts, crowds and seasons and checks the library's rules after every call.
Each suite was run against deliberately broken copies of its library to show it catches them.
EternalSeed and BreathEngine also carry a few symbolic proofs, run with Halmos, for rules simple
enough for the solver to prove for every input.

**Not done yet.** No external audit and no test-network deployment. No formal verification of the
solvers' search or projection, which is too deep for the symbolic tools used here.

## Licence

The libraries are under the Business Source License 1.1 until 1 February 2030, when they become
MIT. Until then you are free to read, audit, test, fork and build on them privately. Only a live
deployment that takes other people's money needs a separate licence. The tests are MIT from day
one.

The date is there to protect the work while it is young and unaudited, not to keep builders out.
If you want to build on these primitives, or help take them forward, get in touch. The aim is a
small team around them, and licence terms are part of that conversation.

Contact: dybl7@proton.me, or dybl777 on Discord.
