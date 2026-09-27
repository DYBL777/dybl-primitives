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

## Licence

The libraries are under the Business Source License 1.1 until 1 February 2030, when they become
MIT. Until then you are free to read, audit, test, fork and build on them privately. Only a live
deployment that takes other people's money needs a separate licence. The tests are MIT from day
one.

The date is there to protect the work while it is young and unaudited, not to keep builders out.
If you want to build on these primitives, or help take them forward, get in touch. The aim is a
small team around them, and licence terms are part of that conversation.

Contact: dybl7@proton.me, or dybl777 on Discord.
