// SPDX-License-Identifier: BUSL-1.1
// Licensed under the Business Source License 1.1
// Licensor:       DYBL Foundation
// Licensed Work:  BreathEngine.sol
// Change Date:    1 February 2030
// Change License: MIT

pragma solidity ^0.8.24;

/**
 * @title  BreathEngine
 * @author DYBL Foundation
 * @notice Autonomous forward-projecting distribution rate solver.
 *
 *         The BreathEngine answers one question every period:
 *         "Given my current stock, my obligation floor, the periods remaining,
 *          and my estimated inflow per period, what is the maximum rate I can
 *          safely distribute this period without breaching the floor at maturity?"
 *
 *         This question, the Autonomous Distribution Rate Problem (ADRP), is
 *         present in every DeFi protocol that holds funds and has obligations.
 *         To our knowledge, no production protocol answers it autonomously and
 *         forward-projecting. BreathEngine does.
 *
 * @dev    WHAT THIS LIBRARY CONTAINS
 *
 *         Five functions. No state. No storage reads. No dependencies.
 *
 *         `sim()`            Simulates pot evolution over N periods at a given rate.
 *                            Used internally by `solve()`. Internal like everything
 *                            here; hosts that want it callable for off-chain tooling
 *                            should expose it via a public wrapper function.
 *
 *         `solve()`          24-iteration geometric binary search. Returns the maximum
 *                            safe distribution rate in BPS such that sim(stock, rate, N)
 *                            >= floor. Convergence guaranteed for maxBreathBps < 2^24
 *                            (~16.7M). IMPORTANT: solve() does NOT guarantee a nonzero
 *                            return. On structural insolvency it returns 0, and it can
 *                            also return 0 for a SOLVENT state with zero headroom. See
 *                            the HOST INTEGRATION NOTE and isInsolvent() below.
 *
 *         `isInsolvent()`    The insolvency predicate: true when even distributing
 *                            nothing cannot reach the floor. This is the test a host
 *                            must pair with a zero return from solve() before treating
 *                            it as distress.
 *
 *         `updateEMA()`      3:1 weighted EMA for the caller's revenue estimate.
 *                            Caller maintains the state variable.
 *
 *         `potHealth()`      Returns stock as BPS of the obligation floor. Sentinel
 *                            type(uint256).max when floor == 0.
 *
 * @dev    SUPPORTED INPUT DOMAIN
 *
 *         `maxBreathBps <= BPS_DENOM (10000)`. The convergence bound (2^24) is much
 *         wider, and values above 10000 still converge and remain floor-safe (the
 *         search verifies every advance directly against sim()), but MAXIMALITY IS NOT
 *         VERIFIED outside the supported domain. Above 100% the per-period clamp region
 *         dominates: once `lost` reaches endStock the period pins to zero and sim
 *         flattens to revPerPeriod, so the search runs in a region this library does not
 *         characterise. No non-monotone case has been produced (a sweep of rates to
 *         40000 across many configurations found none), so the restriction is caution
 *         rather than a demonstrated failure. Rates over 100% are semantically
 *         meaningless for real hosts. Supported: 0-10000. Larger values: converge,
 *         floor-safe, maximality unverified.
 *
 *         `periods`: gas inside solve() is linear in periods at roughly 8,300 gas per
 *         period (one worst-case projection plus 24 binary-search iterations, each
 *         simulating the full horizon: 25 sims per solve).
 *         Measured: ~246k gas at periods = 29, ~8.29M gas at periods = 1000. Around
 *         3,600 periods exceeds a 30M gas block. The BullsEth monolith was structurally
 *         capped at 29; this library accepts any value and does not revert. Supported:
 *         periods <= 366 (covers every daily-for-a-year design at roughly 3M gas per
 *         solve). Hosts deriving periods from configuration or user-influenced values
 *         must bound them before calling.
 *
 * @dev    OVERFLOW ANALYSIS (sim())
 *
 *         Three potential overflow sites in sim():
 *
 *         1. `lost` calculation:
 *            maximum numerator = stock * breathBps * (BPS_DENOM - seedBps)
 *            At stock = 10^18, breathBps = 10000, BPS_DENOM = 10000:
 *            numerator = 10^18 * 10^4 * 10^4 = 10^26, well below uint256 max ~1.16e77.
 *            Safe at any realistic token magnitude.
 *
 *         2. `endStock += revPerPeriod`:
 *            If revPerPeriod is pathologically large (approaching type(uint256).max),
 *            adding it to endStock could overflow. Solidity 0.8.x checked arithmetic
 *            reverts on overflow, so funds are not at risk, but the simulation would
 *            revert rather than return a result.
 *            Overflow bound: revPerPeriod <= type(uint256).max - endStock.
 *            In practice: revPerPeriod is an EMA of actual protocol revenue. At any
 *            realistic revenue magnitude for a 6-decimal USDC protocol (max ~10^15
 *            per period), this bound is unreachable by approximately 60 orders of
 *            magnitude. The host must not pass synthetic or uncapped values.
 *
 *         3. `revPerPeriod * periods` in the seedBps >= BPS_DENOM early return:
 *            The multiplication is checked in its own right, so the product must fit:
 *            revPerPeriod <= type(uint256).max / periods.
 *            This is NOT a tighter constraint than site 2, and it would be wrong to
 *            say the early return overflows sooner than the loop it stands in for.
 *            The two revert on exactly the same inputs: a product overflow implies
 *            the sum overflows, and the loop's checked additions accumulate to the
 *            same total, so both revert precisely when
 *            stock + revPerPeriod * periods > type(uint256).max.
 *            Within the supported domain (periods <= 366) and at realistic USDC
 *            revenue magnitudes this is unreachable by roughly 60 orders of
 *            magnitude. Solidity 0.8.x reverts on overflow, so funds are not at
 *            risk, but the simulation would revert rather than return.
 *
 *         Loop magnitude is covered under SUPPORTED INPUT DOMAIN above: value
 *         magnitudes are safe far beyond realistic inputs, but gas grows linearly
 *         with `periods` and is the binding constraint long before overflow is.
 *
 * @dev    HOST INTEGRATION NOTE: solve() can return 0, and zero is ambiguous
 *
 *         The original DYBL monolith solver pattern clamped its result to a
 *         breathRailMin rail and kept distributing minimal prizes even when the
 *         obligation floor was unreachable, emitting a SolverDistress event
 *         alongside. BullsEth REMOVED that clamp at v1.14 (the H-06 rail release):
 *         its solver now honours a sub-rail answer and returns 0 on structural
 *         insolvency, matching this library's behaviour exactly. Other suite
 *         contracts may still carry the original clamp pattern; when porting,
 *         check the specific host rather than assuming either behaviour.
 *
 *         BreathEngine.solve() has no minimum-rail concept. On structural insolvency
 *         it returns 0. A host that ports from the original clamp pattern by swapping
 *         in the library gets a different game: prizes drop to literally zero in
 *         distress instead of continuing at the rail minimum.
 *
 *         STATED NON-PROPERTY: solve() does NOT guarantee a nonzero return rate.
 *
 *         For a minimum-prize guarantee, the host applies:
 *           rate = max(BreathEngine.solve(...), breathRailMin)
 *
 *         Return value 0 has five distinct meanings:
 *           (a) stock == 0
 *           (b) periods == 0
 *           (c) maxBreathBps == 0
 *           (d) structural insolvency: even at rate 0 the floor is unreachable
 *           (e) solvent, zero headroom: rate 0 reaches the floor but any positive
 *               rate would breach it (e.g. stock == floor with no revenue)
 *
 *         (d) and (e) are indistinguishable from the return value alone, which is
 *         why distress detection must use the insolvency predicate, not the rate:
 *
 *           uint256 rate = BreathEngine.solve(stock, floor, periods, rev, seedBps, maxB);
 *           if (rate == 0 && BreathEngine.isInsolvent(stock, floor, periods, rev, seedBps)) {
 *               emit SolverDistress(currentPeriod, stock, floor, periods);
 *           }
 *
 *         Testing `rate == 0` together with nonzero inputs (an earlier documented
 *         pattern) over-fires: it classifies case (e), a solvent
 *         protocol at exactly its floor, as distress.
 *
 * @dev    BOUNDARY NOTE FOR PORTERS: exact equality is treated as solvent
 *
 *         solve() tests `worstCase < floor` for insolvency, so worstCase == floor
 *         proceeds to the search (the answer may still legitimately be 0, or a small
 *         positive rate where integer truncation makes it free). The BullsEth monolith
 *         tests `projEnd <= floor` and treats exact equality as insolvent, returning 0
 *         with a distress signal. Differential tests between the two will diverge at
 *         this single boundary point. The floor guarantee holds on both sides.
 *
 * @dev    HARDENED ACROSS THE DYBL SUITE
 *
 *         Developed and hardened across repeated triple-audit passes within the DYBL suite:
 *         BullsEth, Lettery777, Weather32 1Y, Pick432 1Y, NearestTheETH,
 *         Lettery_Aave_1Y. Suite contracts are in pre-deployment audit hardening.
 */
library BreathEngine {

    uint256 internal constant SOLVER_ITERS = 24;
    uint256 internal constant BPS_DENOM    = 10_000;
    uint256 internal constant EMA_WEIGHT   = 3;

    /**
     * @notice Simulates stock evolution over `periods` at a constant distribution rate.
     *
     * @dev    Per-period: net_loss = stock * breathBps * (BPS_DENOM - seedBps)
     *                                / (BPS_DENOM * BPS_DENOM)
     *         endStock -= lost; endStock += revPerPeriod.
     *
     *         DIRECTION OF ERROR, and the scope of it matters. Integer truncation
     *         floors `lost`, so this projection books marginally less loss than exact
     *         rational arithmetic would.
     *
     *         WITHIN THIS LIBRARY THAT COSTS NOTHING. solve() tests every candidate
     *         rate against sim() directly and only advances on a verified result, so
     *         the floor guarantee is exact with respect to this model. It cannot be
     *         missed by rounding here.
     *
     *         The gap appears where a HOST's real per-period arithmetic differs from
     *         sim's single floored step. A host computing its pool and its seed in two
     *         separately floored steps loses at least as much as sim models and usually
     *         more, so its real stock lands at or below this projection, never above.
     *
     *         BULLSETHCRE IS THE CANONICAL EXAMPLE OF SUCH A HOST, not an exception to
     *         this. Its projection `_simGeomPot` uses the single floored step, but its
     *         settlement path floors twice: the weekly pool is floored out of the pot,
     *         then the seed rollover is floored out of that already-floored pool. Net
     *         per-period loss is therefore floor(pool) minus floor(seed on that pool),
     *         which is exactly the two-step pattern described above. Measured over 29
     *         draws at pot sizes of 10k, 100k and 1M USDC, breath rates 500, 1000 and
     *         1500 bps, seed 1000 bps and per-draw revenue of one percent of the pot:
     *         the settled pot ends 3 to 11 wei below the projection. Different
     *         parameters give different figures of the same shape, so reproduce with
     *         your own rather than relying on these.
     *
     *         What the differential fidelity suite proves is a different and narrower
     *         thing: that this library introduces NO divergence relative to the
     *         monolith's own projection function. It compares one projection against
     *         another and cannot speak to settlement arithmetic at all.
     *
     *         Two ways to close the gap, and a host should pick one deliberately.
     *         Compute per-period net loss in a single floored step, so settlement
     *         matches this model exactly; that is the cleaner choice for a new host.
     *         Or pad the floor passed to solve() by a wei or two per remaining period;
     *         that is the practical choice when porting arithmetic that already exists.
     *         Either way, a host shape deserves one differential test between sim() and
     *         its own settlement path, the same way this library is tested against the
     *         monolith's projection.
     *
     *         OVERFLOW: lost calculation is safe at any realistic token magnitude.
     *         revPerPeriod addition: safe at realistic revenue magnitudes (see OVERFLOW
     *         ANALYSIS in library NatSpec). Do not pass pathologically large values.
     *         GAS: linear in `periods`; see SUPPORTED INPUT DOMAIN in library NatSpec.
     *
     *         seedBps >= BPS_DENOM: zero net decay, returns stock + revPerPeriod * periods.
     *
     *         PORTERS: that early return is load-bearing above BPS_DENOM, not merely
     *         a shortcut. For seedBps > BPS_DENOM the loop's `BPS_DENOM - seedBps`
     *         term underflows, so the early return is what keeps those inputs total
     *         whenever periods >= 1 (at periods == 0 the loop body never runs, so the
     *         question does not arise). At exactly BPS_DENOM the loop would agree,
     *         since `lost` is 0, but at higher gas. Keep it.
     *
     * @param  stock        Current stock (base token units).
     * @param  breathBps    Distribution rate to simulate (BPS, 0-10000).
     * @param  periods      Number of periods to simulate.
     * @param  revPerPeriod Estimated inflow added each period. Must be a realistic revenue
     *                      figure (EMA recommended). Do not pass type(uint256).max or
     *                      uncapped synthetic values.
     * @param  seedBps      Rollover fraction (BPS). Pass 0 for no rollover.
     * @return endStock     Projected stock after `periods` periods.
     */
    function sim(
        uint256 stock,
        uint256 breathBps,
        uint256 periods,
        uint256 revPerPeriod,
        uint256 seedBps
    ) internal pure returns (uint256 endStock) {
        if (seedBps >= BPS_DENOM) return stock + revPerPeriod * periods;
        endStock = stock;
        for (uint256 i = 0; i < periods; i++) {
            uint256 lost = endStock * breathBps * (BPS_DENOM - seedBps)
                           / (BPS_DENOM * BPS_DENOM);
            endStock = endStock > lost ? endStock - lost : 0;
            endStock += revPerPeriod;
        }
    }

    /**
     * @notice Returns the maximum distribution rate in BPS such that the stock
     *         projected over `periods` periods remains >= `floor` at maturity.
     *         Convergence guaranteed for maxBreathBps < 2^24 (~16.7M BPS).
     *
     * @dev    24-iteration binary search with ceiling midpoint.
     *         Returns 0 on structural insolvency (see HOST INTEGRATION NOTE).
     *
     *         PORTERS: the `worstCase < floor` early return is load-bearing, not an
     *         optimisation. It is the only thing guaranteeing that the search never
     *         evaluates `hi = mid - 1` with mid == 0. Remove it and an insolvent input
     *         drives lo and hi to 0, where mid == 0, sim() fails the floor test, and
     *         the decrement underflows and reverts instead of returning 0.
     *         SCOPE: that revert occurs for every maxBreathBps <= 2^24 - 2, which
     *         covers the whole supported domain and all but the top point of the
     *         convergence domain. `hi + 1` halves each iteration, so hi reaches 0 at
     *         iteration floor(log2(maxBreathBps + 1)); at maxBreathBps >= 2^24 - 1
     *         the 24 iterations are exhausted before mid reaches 0 and a guardless
     *         search returns 0 without reverting. Keep the guard either way.
     *
     *         Return value 0 has five distinct meanings:
     *           (a) stock == 0
     *           (b) periods == 0
     *           (c) maxBreathBps == 0
     *           (d) structural insolvency
     *           (e) solvent, zero headroom (rate 0 reaches the floor; 1 bps breaches)
     *         (d) and (e) cannot be told apart from the return value. Use
     *         isInsolvent() to distinguish them before signalling distress.
     *
     * @param  stock        Current stock.
     * @param  floor        Minimum required stock at maturity.
     * @param  periods      Periods remaining until maturity.
     * @param  revPerPeriod EMA revenue estimate per period.
     * @param  seedBps      Rollover fraction (BPS). Pass 0 if unused.
     * @param  maxBreathBps Upper rail. Supported domain <= 10000; convergence
     *                      guaranteed for maxBreathBps < 2^24 (see SUPPORTED INPUT
     *                      DOMAIN in library NatSpec).
     * @return safeBps      Maximum safe distribution rate. Zero on structural
     *                      insolvency, and possibly zero when solvent with no headroom.
     */
    function solve(
        uint256 stock,
        uint256 floor,
        uint256 periods,
        uint256 revPerPeriod,
        uint256 seedBps,
        uint256 maxBreathBps
    ) internal pure returns (uint256 safeBps) {
        if (stock == 0 || periods == 0) return 0;
        if (floor == 0) return maxBreathBps;
        uint256 worstCase = sim(stock, 0, periods, revPerPeriod, seedBps);
        if (worstCase < floor) return 0;
        uint256 lo = 0;
        uint256 hi = maxBreathBps;
        for (uint256 i = 0; i < SOLVER_ITERS; i++) {
            uint256 mid = (lo + hi + 1) / 2;
            if (sim(stock, mid, periods, revPerPeriod, seedBps) >= floor) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return lo;
    }

    /**
     * @notice True when the position is structurally insolvent: even distributing
     *         nothing for all remaining periods cannot reach the floor.
     *
     * @dev    The predicate a host must pair with a zero return from
     *         solve() before signalling distress. solve() returns 0 both on structural
     *         insolvency and on solvent-zero-headroom states (stock at exactly its
     *         floor with no revenue, for example); testing the rate alone over-fires.
     *         Hosts should not have to re-derive this predicate to use the library
     *         correctly, so it ships in the library:
     *
     *           if (rate == 0 && BreathEngine.isInsolvent(stock, floor, periods, rev, seedBps)) {
     *               // genuine distress
     *           }
     *
     *         Costs one sim() (linear in periods, same as one search probe).
     *
     * @param  stock        Current stock.
     * @param  floor        Minimum required stock at maturity.
     * @param  periods      Periods remaining until maturity.
     * @param  revPerPeriod EMA revenue estimate per period.
     * @param  seedBps      Rollover fraction (BPS). Pass 0 if unused.
     * @return insolvent    True when sim at rate 0 lands below the floor.
     */
    function isInsolvent(
        uint256 stock,
        uint256 floor,
        uint256 periods,
        uint256 revPerPeriod,
        uint256 seedBps
    ) internal pure returns (bool insolvent) {
        return sim(stock, 0, periods, revPerPeriod, seedBps) < floor;
    }

    /**
     * @notice Updates a 3:1 weighted exponential moving average.
     *         newEMA = (prevEMA * 3 + current) / 4
     *         Half-life at zero revenue: ~2.4 periods.
     *
     * @param  prevEMA  Previous EMA value. The caller owns and stores this state.
     * @param  current  This period's observed value.
     * @return newEMA   Updated EMA. The caller stores it for the next period.
     */
    function updateEMA(
        uint256 prevEMA,
        uint256 current
    ) internal pure returns (uint256 newEMA) {
        return (prevEMA * EMA_WEIGHT + current) / (EMA_WEIGHT + 1);
    }

    /**
     * @notice Returns stock as BPS of the obligation floor.
     *         10000 = at floor. 20000 = 2x floor. Below 10000 = distress.
     *         Returns type(uint256).max when floor == 0 (no obligation set).
     *
     * @dev    Integer division floors the result: healthBps can under-read the true
     *         ratio by up to 1 bps, never over-read. This cannot change the outcome
     *         of any comparison against an integer bps threshold (floor(R) >= T iff
     *         R >= T for integer T), so health gates behave exactly as if computed
     *         on the true ratio. The under-read matters only to consumers doing
     *         further arithmetic on the reported value. (Exact multiples do not
     *         truncate: stock at precisely 1.2x floor reads exactly 12000.)
     *
     * @param  stock      Current stock.
     * @param  floor      Obligation floor. Zero means no obligation is set.
     * @return healthBps  Stock as BPS of floor. type(uint256).max when floor == 0.
     */
    function potHealth(
        uint256 stock,
        uint256 floor
    ) internal pure returns (uint256 healthBps) {
        if (floor == 0) return type(uint256).max;
        return stock * BPS_DENOM / floor;
    }
}
