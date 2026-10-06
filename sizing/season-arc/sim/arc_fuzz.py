# SPDX-License-Identifier: MIT
"""
SEASONARC FUZZER. Locates whether the sizing RULE holds across random seasons.

A Python reimplementation of SeasonArc with flat per-ticket income, a jackpot that never hits
and no matching. It does NOT prove the Solidity: pin anything it surfaces in Foundry.

WHAT IT MEASURES. Whether any draw falls, which branch produced each falling draw (so "these
are all the fallback" is measured rather than asserted), and the cost of restoring a climb
after a late arrival against the only pot of money that exists to pay for it.

TWO CHECKS STAND BESIDE EACH OTHER DELIBERATELY. `max_sustainable` is computed by bisection
and again in closed form, with an equivalence check between them, which is what removed an
arbitrary search bound and what would catch a silent change to either.

THE ANCHOR IS SCALED BY THE CHANGE IN FIELD, as the host does before calling the library. A
version of this file without that scaling reported zero falling draws in every row, because
the glide almost never fires from growth when the anchor is carried forward flat.
"""
import random
from math import comb

BPS = 10_000; G_MIN = 10_000; G_MAX = 1_000_000; ITERS = 48
U = 10 ** 6; POT_SHARE = 4 * U; RETURN_BPS = 2990; OPENING = 2500

N = comb(42, 6)
P = {k: comb(6, k) * comb(36, 6 - k) / N for k in range(7)}


def leftover(pot, last_paid, dl, inc, rb, g):
    p, pay = pot, last_paid
    for k in range(dl):
        if k > 0: p += inc
        pay = pay * g // BPS
        if pay >= p: return 0
        p -= pay
        if k + 1 < dl: p += pay * rb // BPS
    return p


def solve(pot, last_paid, dl, inc, rb):
    lo, hi = G_MIN, G_MAX
    for _ in range(ITERS):
        mid = (lo + hi) // 2
        if leftover(pot, last_paid, dl, inc, rb, mid) > 0: lo = mid
        else: hi = mid
        if hi - lo <= 1: break
    return lo


def max_sustainable_bisect(pot, dl, inc, rb):
    """The earlier bisection, kept for comparison. Note the search bound pot*20 is arbitrary, and at
    large magnitudes 64 iterations no longer resolves to the wei: at pot=1e30 it undershoots
    the true answer by roughly 1e12."""
    lo, hi = 0, pot * 20 + inc * dl + 1
    for _ in range(64):
        mid = (lo + hi) // 2
        if mid > 0 and leftover(pot, mid, dl, inc, rb, G_MIN) > 0: lo = mid
        else: hi = mid
    return lo


def max_sustainable_cf(pot, dl, inc, rb):
    """Largest flat payment the pot AND its future income can carry to the end, in closed
    form. No search bound, and constant work regardless of season length.

    DERIVATION. The fallback pays at G_MIN, so the payment is FLAT at P every draw. That
    makes the forward walk a straight line rather than something that needs searching. Each
    non-final draw removes P and returns P*rb/BPS, so the balance standing before draw k is

        p(k) = pot + k*inc - k*P*(BPS-rb)/BPS

    and the walk survives draw k exactly when P < p(k). Rearranged, for every k in 0..dl-1:

        P  <  BPS*(pot + k*inc) / (BPS + k*(BPS-rb))

    The answer is the smallest of those bounds. The right side is (A + kB)/(C + kD), which is
    monotone in k, so the smallest is at one of the two ENDS. Two divisions, not a search.

    Integer floors lose at most one wei of pot per draw, so the true answer sits within dl of
    the closed form. The correction loop below closes that gap over a band of width dl+2,
    which is at most 10 iterations for a 520 draw season, and it only runs when the first
    candidate misses."""
    E = BPS - rb

    def bound(k):
        return (BPS * (pot + k * inc) - 1) // (BPS + k * E)

    cand = max(0, min(bound(0), bound(dl - 1)))
    if cand == 0 or leftover(pot, cand, dl, inc, rb, G_MIN) > 0:
        return cand
    lo, hi = (cand - dl - 2) if cand > dl + 2 else 0, cand
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if mid > 0 and leftover(pot, mid, dl, inc, rb, G_MIN) > 0: lo = mid
        else: hi = mid
    return lo if (lo > 0 and leftover(pot, lo, dl, inc, rb, G_MIN) > 0) else 0


max_sustainable = max_sustainable_cf


def size(pot, last_paid, dl, inc, fix_glide, f, last_field):
    if dl == 1: return pot, "CLOSING"
    if pot == 0: return 0, "POT"
    if last_paid == 0: return pot * OPENING // BPS, "OPENING"
    anchor = last_paid
    if last_field > 0 and f > 0:
        anchor = last_paid * f // last_field          # the host's anchor scaling
    g = solve(pot, anchor, dl, inc, RETURN_BPS)
    if g == G_MIN:
        if fix_glide:
            # 1.1.0: flat pays when flat still fits; the fallback only when it runs dry
            if leftover(pot, anchor, dl, inc, RETURN_BPS, G_MIN) > 0: return anchor, "ARC"
            return max_sustainable(pot, dl, inc, RETURN_BPS), "SUSTAINED"
        return pot // dl, "GLIDE"
    return anchor * g // BPS, "ARC"


def m3_each(amt, f):
    """Match-3's own share per winner: its own pool and its share of the missed jackpot.
    Roll-downs from higher tiers are not modelled, so dollar figures understate match-3;
    comparisons between runs are unaffected."""
    if f == 0: return 0.0
    jp = 0.33 * amt; to_low = 0.30 * jp
    t3 = 0.12 * amt + 0.33 * to_low
    return t3 / (f * P[3])


def season(fields, share, fix_glide):
    n = len(fields)
    pot = roll = last_paid = last_field = misses = 0
    rows = []
    for d in range(1, n + 1):
        f = fields[d - 1]; inc = f * POT_SHARE; pot += inc; m = n - d + 1
        base, bind = size(pot, last_paid, m, inc, fix_glide, f, last_field)
        if share and last_field > 0 and f > last_field and m > 1:
            base = int(base + share * (f - last_field) * POT_SHARE)
        amt = max(0, min(base, pot)); pot -= amt
        release = (misses >= 2) and m > 1
        jp = amt * 3300 // BPS
        roll += 0 if release else jp * 4000 // BPS
        pot += jp * 3000 // BPS + amt * 2000 // BPS
        rows.append(dict(d=d, f=f, amt=amt, pot=pot, each=m3_each(amt / U, f),
                         bind=bind, inc=inc, roll=roll))
        misses = 0 if release else misses + 1
        if f > 0: last_paid, last_field = amt, f
    return rows


def check(rows):
    """P1 failures with the branch that produced each one."""
    binds = {}
    for i in range(1, len(rows) - 1):
        a, b = rows[i - 1], rows[i]
        if b["f"] <= a["f"] or a["f"] == 0: continue
        if b["amt"] < a["amt"]: binds[b["bind"]] = binds.get(b["bind"], 0) + 1
    return binds


SHAPES = ["flat", "growth", "spike", "dead_weeks", "sawtooth", "late_surge",
          "early_surge", "random_walk", "boom_bust", "decline", "collapse"]


def make_field(shape, n, rng):
    base = rng.choice([40, 120, 500, 2000]); f = []; v = float(base)
    spike_at = rng.randint(2, max(2, n - 1))
    for d in range(1, n + 1):
        if shape == "flat": v = base
        elif shape == "growth": v *= rng.uniform(1.00, 1.12)
        elif shape == "decline": v *= rng.uniform(0.90, 1.00)
        elif shape == "spike": v = base * rng.choice([8, 15, 25]) if d == spike_at else base
        elif shape == "collapse": v = base if d < n // 2 else base * rng.uniform(0.01, 0.15)
        elif shape == "dead_weeks": v = 0 if rng.random() < 0.15 else base
        elif shape == "sawtooth": v = base * (3 if d % 4 == 0 else 1)
        elif shape == "late_surge": v = base if d < n - 6 else base * rng.choice([5, 10, 20])
        elif shape == "early_surge": v = base * rng.choice([5, 10]) if d <= 3 else base
        elif shape == "random_walk": v *= rng.uniform(0.6, 1.7)
        elif shape == "boom_bust": v = base * (10 if n // 3 < d < 2 * n // 3 else 1)
        f.append(max(0, int(v)))
    return f


def fuzz(fix_glide, share=0.0, trials=400, seed=11):
    rng = random.Random(seed); tot = {}
    for _ in range(trials):
        sh = rng.choice(SHAPES); n = rng.choice([8, 12, 26, 52, 104])
        for k, v in check(season(make_field(sh, n, rng), share, fix_glide)).items():
            tot[k] = tot.get(k, 0) + v
    return sum(tot.values()), tot


def sec4():
    print("400 random crowd shapes, eleven patterns, five season lengths.")
    print("Property: a draw where the crowd GREW never pays less than the draw before.")
    print()
    print("  version                    draws that fell   by branch")
    for fg, lbl in ((False, "pot/drawsLeft (old rule)"), (True, "as it ships")):
        t, by = fuzz(fg)
        print("  {:<26} {:>15d}   {}".format(lbl, t, by if by else "-"))
    print()
    print("  healthy arrivals, where the fix must do nothing:")
    for at in (15, 30):
        for mult in (2, 5, 10):
            fs = [1000] * (at - 1) + [1000 * mult] * (52 - at + 1)
            a = season(fs, 0.0, False); b = season(fs, 0.0, True)
            same = all(x["amt"] == y["amt"] for x, y in zip(a, b))
            print("    {:>2}x at draw {:>2}: identical={}".format(mult, at, same))


def sec5():
    print()
    print("Late arrival flattens the remaining climb. 104 draws, 1,000 players,")
    print("1.7x arrives at draw 86 and stays. Match-3's own share per winner")
    print("(roll-downs not modelled):")
    base = season([1000] * 104, 0.0, True)
    arr = season([1000] * 85 + [1700] * 19, 0.0, True)
    for lbl, r in (("no arrival", base), ("arrival   ", arr)):
        print("  {}  ".format(lbl) + "  ".join(
            "d{}=${:>6.2f}".format(d, r[d - 1]["each"]) for d in (86, 90, 95, 103))
            + "   finale=${:,.0f}".format(r[-1]["amt"] / U))

    print()
    print("  IS IT FUNDABLE? Holding per-winner value on the no-arrival path after a k-fold")
    print("  arrival needs every remaining payment multiplied by k. The extra crowd supplies")
    print("  (k-1)*f*POT_SHARE per draw and the extra demand is (k-1)*payments. The (k-1)")
    print("  cancels, so it is absorbable from income alone if and only if remaining income")
    print("  covers remaining payments net of the {:.1f}% return credit.".format(RETURN_BPS / 100))
    print()
    print("   from draw    income      payments net    covered")
    for start in (86, 70, 50, 30, 11):
        m = 104 - start + 1
        inc = 1000 * POT_SHARE * m
        net = sum(x["amt"] - x["amt"] * RETURN_BPS // BPS for x in base[start - 1:])
        print("   {:>9}  ${:>10,.0f}     ${:>11,.0f}    {:>5.0f}%".format(
            start, inc / U, net / U, 100 * inc / net))

    need = 0
    for d in range(86, 104):
        a = arr[d - 1]; t = base[d - 1]["each"]
        if a["each"] < t: need += a["amt"] * (t / a["each"] - 1)
    print()
    closing = arr[-1]["amt"]; stock = arr[-2]["roll"]; ending = closing + stock
    print("   cost of restoring the climb, draws 86-103: ${:,.0f}".format(need / U))
    print("   the closing draw's sized prize:            ${:,.0f}".format(closing / U))
    print("   unwon stockpile going into it:             ${:,.0f}".format(stock / U))
    print("   the ending holds, together:                ${:,.0f}".format(ending / U))
    print("   surplus the arrival itself created:        ${:,.0f}".format(
        (closing - base[-1]["amt"]) / U))
    print("   the cost is {:.2f}x what the ending holds.".format(need / ending))


def sec8():
    print()
    print("Closed form against the bisection it replaces.")
    print("  the fallback's headline case, pot 28,744 / 8 draws left / 4,000 a draw arriving:")
    print("    GLIDE pays          ${:,}".format(28744 // 8))
    print("    closed form         ${:,}".format(max_sustainable_cf(28744, 8, 4000, RETURN_BPS)))
    print("    earlier bisection   ${:,}".format(
        max_sustainable_bisect(28744, 8, 4000, RETURN_BPS)))
    print("    At whole-dollar scale the walk survives 9,605. The contract, at six decimals,")
    print("    computes 9,606.23, and that is the figure the documents quote.")
    rng = random.Random(7); worst = 0; bad = 0
    for _ in range(40000):
        pot = rng.randint(1, 10 ** 14); dl = rng.randint(2, 520); inc = rng.randint(0, 10 ** 12)
        a = max_sustainable_bisect(pot, dl, inc, RETURN_BPS)
        b = max_sustainable_cf(pot, dl, inc, RETURN_BPS)
        if b > 0 and leftover(pot, b, dl, inc, RETURN_BPS, G_MIN) <= 0: bad += 1
        worst = max(worst, abs(a - b))
    print("  40,000 random cases: max difference {}, infeasible answers {}".format(worst, bad))
    big = (10 ** 30, 104, 10 ** 28)
    print("  at pot=1e30 the earlier bisection undershoots by {:,} wei; closed form is exact.".format(
        max_sustainable_cf(*big, RETURN_BPS) - max_sustainable_bisect(*big, RETURN_BPS)))


if __name__ == "__main__":
    sec4(); sec5(); sec8()
