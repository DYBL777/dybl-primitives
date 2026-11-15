// SPDX-License-Identifier: MIT
// SeasonArc 1.1.6, ported line for line from src/SeasonArc.sol to JavaScript BigInt.
//
// Same arithmetic as the compiled library: whole numbers, division rounding down, and a revert
// (a thrown SeasonArcRevert) wherever the contract would revert, including overflow past
// 2^256 - 1. lab/vectors.json holds cases with the compiled library's answers, and
// test/Vectors.t.sol checks the library against every one, so this port and the library are
// held to the same file:
//
//   node lab/seasonarc.js check     every case in lab/vectors.json, against this port
//   node lab/seasonarc.js vectors   write the cases again (then run forge test, which checks
//                                   the compiled library against them)
//
// Used by lab/index.html in the browser, and by any host page that wants the library's rule
// without porting it again.

(function (root) {
  "use strict";

  const BPS = 10000n, G_MIN = 10000n, G_MAX = 1000000n, ITERS = 48;
  const MAX = (1n << 256n) - 1n;
  const BIND = ["OPENING", "ARC", "SUSTAINED", "POT", "CLOSING"];

  class SeasonArcRevert extends Error {
    constructor(reason) { super(reason); this.reason = reason; }
  }

  // Solidity 0.8 checked arithmetic.
  function add(a, b) { const r = a + b; if (r > MAX) throw new SeasonArcRevert("Panic(0x11)"); return r; }
  function sub(a, b) { if (b > a) throw new SeasonArcRevert("Panic(0x11)"); return a - b; }
  function mul(a, b) { const r = a * b; if (r > MAX) throw new SeasonArcRevert("Panic(0x11)"); return r; }
  function div(a, b) { if (b === 0n) throw new SeasonArcRevert("Panic(0x12)"); return a / b; }

  function leftover(pot, lastPaid, drawsLeft, income, returnBps, g) {
    let p = pot, pay = lastPaid;
    for (let k = 0n; k < drawsLeft; k++) {
      if (k > 0n) p = add(p, income);
      pay = div(mul(pay, g), BPS);
      if (pay >= p) return 0n;
      p = sub(p, pay);
      if (add(k, 1n) < drawsLeft) p = add(p, div(mul(pay, returnBps), BPS));
    }
    return p;
  }

  function solve(pot, lastPaid, drawsLeft, income, returnBps) {
    let lo = G_MIN, hi = G_MAX;
    for (let i = 0; i < ITERS; i++) {
      const mid = div(add(lo, hi), 2n);
      if (leftover(pot, lastPaid, drawsLeft, income, returnBps, mid) > 0n) lo = mid;
      else hi = mid;
      if (hi - lo <= 1n) break;
    }
    return lo;
  }

  function maxSustainable(pot, drawsLeft, income, returnBps) {
    const spend = sub(BPS, returnBps);
    const first = div(sub(mul(BPS, pot), 1n), BPS);
    const last = div(sub(mul(BPS, add(pot, mul(sub(drawsLeft, 1n), income))), 1n),
                     add(BPS, mul(sub(drawsLeft, 1n), spend)));
    const cand = first < last ? first : last;
    if (cand === 0n) return 0n;
    if (leftover(pot, cand, drawsLeft, income, returnBps, G_MIN) > 0n) return cand;
    let lo = cand > add(drawsLeft, 2n) ? cand - drawsLeft - 2n : 0n;
    let hi = cand;
    while (hi - lo > 1n) {
      const mid = div(add(lo, hi), 2n);
      if (mid > 0n && leftover(pot, mid, drawsLeft, income, returnBps, G_MIN) > 0n) lo = mid;
      else hi = mid;
    }
    if (lo === 0n) return 0n;
    return leftover(pot, lo, drawsLeft, income, returnBps, G_MIN) > 0n ? lo : 0n;
  }

  // SeasonArc.size. Returns { amount, bind } with bind an index into BIND, or throws
  // SeasonArcRevert where the library reverts.
  function size(pot, lastPaid, drawsLeft, income, returnBps, openingBps) {
    pot = BigInt(pot); lastPaid = BigInt(lastPaid); drawsLeft = BigInt(drawsLeft);
    income = BigInt(income); returnBps = BigInt(returnBps); openingBps = BigInt(openingBps);
    if (returnBps >= BPS) throw new SeasonArcRevert("BadReturnShare()");
    if (openingBps > BPS) throw new SeasonArcRevert("OpeningShareTooLarge()");
    if (drawsLeft === 0n) return { amount: 0n, bind: 3 };
    if (drawsLeft === 1n) return { amount: pot, bind: 4 };
    if (pot === 0n) return { amount: 0n, bind: 3 };
    if (lastPaid === 0n) return { amount: div(mul(pot, openingBps), BPS), bind: 0 };
    const g = solve(pot, lastPaid, drawsLeft, income, returnBps);
    const amount = div(mul(lastPaid, g), BPS);
    if (g === G_MIN) {
      if (leftover(pot, lastPaid, drawsLeft, income, returnBps, G_MIN) > 0n) return { amount, bind: 1 };
      return { amount: maxSustainable(pot, drawsLeft, income, returnBps), bind: 2 };
    }
    return { amount, bind: 1 };
  }

  // ── The cases in lab/vectors.json ──────────────────────────────────────────────────────
  // Fixed edges first, then seeded random cases. Deterministic: the same file every run.

  function cases() {
    const out = [];
    const push = (pot, last, dl, inc, ret, open) => out.push([pot, last, dl, inc, ret, open].map(BigInt));
    const U = 1000000n;
    // Edges: each branch of size(), the reverts, and the boundaries around them.
    for (const dl of [0n, 1n, 2n, 3n, 52n]) for (const pot of [0n, 1n, 1000n * U]) for (const last of [0n, 1n, 100n * U])
      push(pot, last, dl, 10n * U, 2990n, 2500n);
    for (const ret of [0n, 1n, 2990n, 9999n, 10000n, 20000n]) push(5000n * U, 100n * U, 10n, 50n * U, ret, 2500n);
    for (const open of [0n, 1n, 2500n, 10000n, 10001n]) push(5000n * U, 0n, 10n, 50n * U, 2990n, open);
    push(MAX, 0n, 10n, 0n, 0n, 1n);                    // pot * 1: fits
    push(MAX, 0n, 10n, 0n, 0n, 2n);                    // pot * openingBps overflows
    push(MAX / BPS, 0n, 10n, 0n, 0n, BPS);             // just fits
    push(MAX / BPS + 1n, 0n, 10n, 0n, 0n, BPS);        // one past
    push(MAX / 2n, 1n, 3n, MAX / 2n, 0n, 0n);          // income added in the walk overflows
    push(1n, 1n, 2n, 0n, 0n, 0n);                      // smallest pot and payment
    push(2n, 1n, 2n, 0n, 0n, 0n);
    push(1000n * U, 1000n * U, 5n, 0n, 0n, 2500n);     // last payment as big as the pot: sustained
    push(1000n * U, 1n, 156n, 0n, 0n, 2500n);          // tiny last payment: arc at the ceiling
    push(1000n * U, 10n * U, 156n, 5n * U, 2990n, 2500n);
    // Seeded random: magnitudes spread over many orders, as hosts see them.
    let s = 0x5ea50aa1n;
    const rnd = () => { s = (s * 6364136223846793005n + 1442695040888963407n) & ((1n << 64n) - 1n); return s >> 11n; };
    const span = (lo, hi) => lo + rnd() % (hi - lo + 1n);
    const logU = (maxPow) => { const p = span(0n, maxPow); return span(0n, 10n ** p); };
    for (let i = 0; i < 1500; i++) {
      const dl = i % 10 === 0 ? span(2n, 160n) : span(2n, 60n);
      const pot = logU(15n);                            // up to $1bn in 6-decimal units
      const roll = rnd() % 10n;
      const last = roll === 0n ? 0n : roll === 1n ? span(1n, 1000n) : logU(14n);
      const inc = rnd() % 5n === 0n ? 0n : logU(13n);
      const ret = rnd() % 4n === 0n ? 0n : span(0n, 9999n);
      const open = span(0n, 10000n);
      push(pot, last, dl, inc, ret, open);
    }
    return out;
  }

  function run(c) {
    try { const r = size(...c); return { amount: r.amount, bind: r.bind, revert: "" }; }
    catch (e) { if (e instanceof SeasonArcRevert) return { amount: 0n, bind: 0, revert: e.reason }; throw e; }
  }

  function vectors() {
    const cols = { pot: [], lastPaid: [], drawsLeft: [], income: [], returnBps: [], openingBps: [],
                   amount: [], bind: [], reverts: [] };
    for (const c of cases()) {
      const r = run(c);
      ["pot", "lastPaid", "drawsLeft", "income", "returnBps", "openingBps"].forEach((k, i) => cols[k].push(c[i].toString()));
      cols.amount.push(r.amount.toString()); cols.bind.push(String(r.bind)); cols.reverts.push(r.revert ? "1" : "0");
    }
    return { library: "SeasonArc 1.1.6",
             instructions: "0xc4f7e21e0da4c59421372ffc0770135c73369dd7d2498c115b6a0281c0b6b2fb",
             note: "Inputs and the library's answers, one case per index. reverts=1: the library reverts. bind: 0 OPENING, 1 ARC, 2 SUSTAINED, 3 POT, 4 CLOSING. Checked against the compiled library by test/Vectors.t.sol.",
             count: cols.pot.length, ...cols };
  }

  function check(v) {
    let bad = 0;
    for (let i = 0; i < v.count; i++) {
      const c = ["pot", "lastPaid", "drawsLeft", "income", "returnBps", "openingBps"].map(k => BigInt(v[k][i]));
      const r = run(c);
      const ok = v.reverts[i] === "1" ? r.revert !== "" : (r.revert === "" && r.amount.toString() === v.amount[i] && String(r.bind) === v.bind[i]);
      if (!ok) { bad++; if (bad <= 5) console.error("case", i, "differs:", c.map(String), r); }
    }
    return bad;
  }

  const api = { size, leftover, BIND, BPS, SeasonArcRevert, cases, vectors, check };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.SeasonArc = api;

  if (typeof require === "function" && typeof module === "object" && require.main === module) {
    const fs = require("fs"), path = require("path");
    const file = path.join(__dirname, "vectors.json");
    const cmd = process.argv[2];
    if (cmd === "vectors") {
      const v = vectors();
      fs.writeFileSync(file, JSON.stringify(v, null, 1) + "\n");
      console.log("wrote", v.count, "cases to", file);
    } else if (cmd === "check") {
      const v = JSON.parse(fs.readFileSync(file, "utf8"));
      const bad = check(v);
      console.log(bad === 0 ? `all ${v.count} cases match` : `${bad} of ${v.count} cases differ`);
      process.exit(bad === 0 ? 0 : 1);
    } else {
      console.log("usage: node lab/seasonarc.js check | vectors");
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
