# Origin

In my own words, because the code can show what the seed and the breath do, but not where they
came from.

From the research I did, people play a lottery for three reasons. The jackpot, and the dream that comes with
it. The entertainment, the weekly ritual. And the odds, the sense that this week it could be you.
The odds and the fun I could already give people. The harder question was how to make the jackpot
bigger, the way a Powerball jackpot grows when it rolls.

My answer was to stop paying out in a way that takes the pot back to nothing. If a game keeps
something back every time, the next draw doesn't start from zero, and what's kept can be put to
work and grow. That became the Eternal Seed. The first contract I built around it was a
42-character lottery, Lettery_S1, and the whole suite comes from there.

Once I had the seed I kept finding versions of it, and within the first couple of months, with AI
assistance, I had written down sixteen. A floor that isn't paid out. A flow, where a share of
every prize goes back in. The money held back put to work, earning while it waits. Most of the
variants are still just names. In time they sorted themselves into two plain questions: how does
the pot keep money back, and how does its season end? That is the map EternalSeed.sol carries now.

Protect it, grow it, pace it.

The breath came from the next question: once you're keeping something back, how much should go out
each draw? My first games answered with a timetable. Build the pot for years, then pay it out
harder at the end. It worked on paper and it was brittle, because a timetable is a promise made
before anyone knows who will turn up. So the breath changed from a schedule into a reading. Look
at what's actually there, the pot, the income, the draws left, and pay what that can carry. A game
that breathes in when people come and out when they go, instead of one that promises a number and
hopes.

The first version, the one that has to meet a floor by the end of a season, grew up in the
prediction games. Crypto42 learned to correct itself, Pick432 first solved for the floor, the
NearestTheETH games carried it, and BullsEth gave it its full form. They weren't lotteries, which
is how I knew it wasn't just a lottery idea. Then the same question came back in a different shape
for different games. A game with no end date needs to know what it can afford forever. A game with
a last draw wants its prizes to rise toward it. A game spending a savings pot down to zero wants
equal shares. So there are four sizing libraries, each answering that question for a different
kind of game. Each grew out of a game, and three are in this repository so far. All of them are
tested only in their own test suites, and none has run on a test network yet.

I started in November 2025, and I'm about twenty contracts in. The seed and the breath grew with
every game, in tandem with everything else they need before anyone should trust them with money:
what happens when a lender freezes, when the randomness doesn't arrive, when a draw has to be
stopped halfway, when a game winds down and somebody has to be paid first. The core ideas were
there at the start. Each game sharpened them, and the rest was earning the right to run them.

One thing I wanted from the beginning. When things get thin, fewer players or weaker yield, the
seed should be there for the people who stay. You've got to be in it to win it, and if you're in
it, it's worth being there.

The names here, the seed and the breath among them, are the working names I've built with. They
are open to change, and I'd expect a team to have views on them.

I'm not a developer. I've studied blockchain for eight years and Chainlink for six, and watched a
lot of people get hurt by projects they trusted. I came to this as a creative, an inventor and a
therapist of thirty years, and I think that shows in what I look for: patterns, and how a design
feels from the player's side. Fairness, trust, transparency, immutability where it's possible, and
rewarding the people who stay were never up for negotiation. The Solidity was written with AI
assistance under my direction; the ideas, and the choices about what these libraries would and
wouldn't do, are mine.
