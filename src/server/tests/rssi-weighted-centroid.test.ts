/**
 * Tests for src/services/algorithms/rssi-weighted-centroid.ts
 *
 * Pure unit tests — no database, no MQTT, no async.
 *
 * ── 4-Wave Model ──────────────────────────────────────────────────────────────
 *
 * A real traversal produces four independent "waves" that interact:
 *
 *   TWO  Temporal Wave Outside  — when the outside lighthouse detects scans
 *   TWI  Temporal Wave Inside   — when the inside  lighthouse detects scans
 *   RWO  RSSI Wave Outside      — how the outside RSSI changes over time
 *   RWI  RSSI Wave Inside       — how the inside  RSSI changes over time
 *
 * TWO and TWI together determine the temporal centroid separation (same as
 * Algorithm 1).  RWO and RWI add two orthogonal pieces of information:
 *
 *   (a) RSSI-weighted centroids: strong-signal scans pull the centroid toward
 *       them, either amplifying or opposing the temporal separation.
 *
 *   (b) RSSI trend: a falling outside RSSI + rising inside RSSI agrees with
 *       an "in" traversal (person moving away from outside, toward inside).
 *       Disagreement degrades the rssiTrendConsistencyFactor.
 *
 * ── RSSI profile conventions ─────────────────────────────────────────────────
 *
 *   "falling"  -50 → -80 dBm  (weight 0.80 → 0.20)  — agrees with "in" for outside
 *   "rising"   -80 → -50 dBm  (weight 0.20 → 0.80)  — agrees with "in" for inside
 *   "flat"     -65 dBm        (weight 0.50 always)   — slope ≈ 0, R² ≈ 0, inconclusive
 *   "null"     no reading     (weight 1.00 always)   — no regression possible
 *
 * For "out" traversal the expected agreement profile is reversed:
 *   inside "falling" + outside "rising"
 *
 * ── Centroid-shift physics ────────────────────────────────────────────────────
 *
 * Baseline temporal setup (used for most RSSI tests):
 *   TWO: center=1000 ms, halfWidth=1000 ms → spans [0,   2000] ms
 *   TWI: center=3000 ms, halfWidth=1000 ms → spans [2000, 4000] ms
 *   Unweighted separation = 2000 ms, cluster duration = 4000 ms → CSF = 0.50
 *
 *   With RWO="falling" and RWI="rising" (agreement):
 *     Outside centroid is pulled EARLIER  → wCSF_outside < 1000 ms
 *     Inside  centroid is pulled LATER    → wCSF_inside  > 3000 ms
 *     Weighted centroid separation > 2000 ms → wCSF > 0.50
 *
 *   With RWO="rising" and RWI="falling" (contradiction):
 *     Outside centroid is pulled LATER    → wCSF_outside > 1000 ms
 *     Inside  centroid is pulled EARLIER  → wCSF_inside  < 3000 ms
 *     Weighted centroid separation < 2000 ms → wCSF < 0.50
 */

import { describe, it, expect } from "bun:test";
import { analyzeRssiWeightedCentroid } from "../src/services/algorithms/rssi-weighted-centroid";
import { analyzeTemporalCentroid } from "../src/services/algorithms/temporal-centroid";
import {
  CONFIDENCE_FACTOR_FLOOR,
  type ScanData,
  type PartitionedCluster,
} from "../src/services/algorithms/types";

// ─── Constants ────────────────────────────────────────────────────────────────

const BASE_TIME = new Date("2025-06-01T12:00:00Z").getTime();
const OUTSIDE_LH = 10;
const INSIDE_LH = 11;
const EPC = "ETEST_RSSI_WAVE0001";
const GROUP_ID = 5;
const HALF_WIDTH_MS = 1000;
const SCANS_PER_WAVE = 20;

// Baseline temporal setup (scenario E-level separation)
const TWO_CENTER = 1000; // ms from BASE_TIME — outside wave centre
const TWI_CENTER = 3000; // ms from BASE_TIME — inside  wave centre

// Wave scenario temporal centres (identical to temporal-centroid test)
const WAVE1_CENTER = 1000;
const SCENARIO_B_W2 = 1500;
const SCENARIO_C_W2 = 2000;
const SCENARIO_D_W2 = 2500;
const SCENARIO_E_W2 = 3000;
const SCENARIO_F_W2 = 4000;

// ─── ID counter ───────────────────────────────────────────────────────────────

let _id = BigInt(10_000);
function nextId(): bigint {
  return _id++;
}

// ─── RSSI profile generators ──────────────────────────────────────────────────

type RssiProfile = "falling" | "rising" | "flat" | "null";

/**
 * Generate the RSSI value for scan index `i` out of `count`.
 *
 *   "falling": −50 → −80 dBm  (linear, perfectly linear → R²=1)
 *   "rising":  −80 → −50 dBm  (linear, perfectly linear → R²=1)
 *   "flat":    −65 dBm        (constant → slope=0, R²=0 → inconclusive)
 *   "null":    null           (no RSSI → weight=1, no regression)
 */
function rssiValue(
  profile: RssiProfile,
  i: number,
  count: number,
): number | null {
  const t = count === 1 ? 0 : i / (count - 1); // 0 → 1
  switch (profile) {
    case "falling":
      return -50 - 30 * t; // -50 at i=0, -80 at i=count-1
    case "rising":
      return -80 + 30 * t; // -80 at i=0, -50 at i=count-1
    case "flat":
      return -65;
    case "null":
      return null;
  }
}

// ─── Wave builder ─────────────────────────────────────────────────────────────

/**
 * Build `count` ScanData entries whose timestamps are evenly spread over
 * [BASE_TIME + centerMs − halfWidthMs, BASE_TIME + centerMs + halfWidthMs].
 *
 * Because timestamps are symmetric around centerMs the arithmetic mean (and
 * the null-RSSI weighted mean) equals exactly BASE_TIME + centerMs.
 *
 * When a non-null RSSI profile is provided the RSSI values are perfectly
 * linear in scan order → R² = 1.0 in the regression.  Because scan order
 * and chronological order are identical this means R² = 1.0 vs. time too.
 */
function makeWave(
  lighthouseId: number,
  centerMs: number,
  rssiProfile: RssiProfile = "null",
  halfWidthMs: number = HALF_WIDTH_MS,
  count: number = SCANS_PER_WAVE,
): ScanData[] {
  return Array.from({ length: count }, (_, i) => {
    const t = count === 1 ? 0 : (i / (count - 1)) * 2 - 1; // −1 → +1
    return {
      id: nextId(),
      lighthouseId,
      epc: EPC,
      rssiDbm: rssiValue(rssiProfile, i, count),
      timestamp: new Date(BASE_TIME + centerMs + t * halfWidthMs),
      timeBasis: "synced" as const,
    };
  });
}

// ─── Cluster builder ──────────────────────────────────────────────────────────

function makeCluster(
  outsideScans: ScanData[],
  insideScans: ScanData[],
): PartitionedCluster {
  const all = [...outsideScans, ...insideScans];
  const times = all.map((s) => s.timestamp.getTime());
  return {
    epc: EPC,
    groupId: GROUP_ID,
    outsideScans,
    insideScans,
    allScans: all,
    clusterStartedAt: new Date(Math.min(...times)),
    clusterEndedAt: new Date(Math.max(...times)),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — Basic properties
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — basic properties", () => {
  const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
  const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
  const cluster = makeCluster(outside, inside);

  it("algorithmId is 'rssi_weighted_centroid'", () => {
    expect(analyzeRssiWeightedCentroid(cluster).algorithmId).toBe(
      "rssi_weighted_centroid",
    );
  });

  it("all factors are within [CONFIDENCE_FACTOR_FLOOR, 1.0]", () => {
    const r = analyzeRssiWeightedCentroid(cluster);
    for (const f of [
      r.centroidSeparationFactor,
      r.clusterSizeFactor,
      r.bilateralCoverageFactor,
      r.rssiTrendConsistencyFactor!,
      r.confidence,
    ]) {
      expect(f).toBeGreaterThanOrEqual(CONFIDENCE_FACTOR_FLOOR);
      expect(f).toBeLessThanOrEqual(1.0);
    }
  });

  it("rssiTrendConsistencyFactor is non-null", () => {
    expect(analyzeRssiWeightedCentroid(cluster).rssiTrendConsistencyFactor).not.toBeNull();
  });

  it("confidence equals the product of all four factors", () => {
    const r = analyzeRssiWeightedCentroid(cluster);
    expect(r.confidence).toBeCloseTo(
      r.centroidSeparationFactor *
        r.clusterSizeFactor *
        r.bilateralCoverageFactor *
        r.rssiTrendConsistencyFactor!,
      10,
    );
  });

  it("metadata contains all required keys", () => {
    const r = analyzeRssiWeightedCentroid(cluster);
    const m = r.metadata as Record<string, unknown>;
    for (const key of [
      "outsideCentroidMs",
      "insideCentroidMs",
      "centroidDeltaMs",
      "clusterDurationMs",
      "outsideScanCount",
      "insideScanCount",
      "rssiWeights",
      "rssiTrend",
    ]) {
      expect(m).toHaveProperty(key);
    }
  });

  it("metadata.rssiTrend contains outside and inside sub-objects", () => {
    const r = analyzeRssiWeightedCentroid(cluster);
    const trend = (r.metadata as Record<string, unknown>)
      .rssiTrend as Record<string, unknown>;
    expect(trend).toHaveProperty("outside");
    expect(trend).toHaveProperty("inside");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — Null RSSI: graceful degradation to Algorithm 1 behaviour
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — null RSSI (baseline degradation)", () => {
  it("weighted centroid equals unweighted centroid when all RSSI are null", () => {
    // With all weights = 1.0 both algorithms must produce the same centroid
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "null");
    const cluster = makeCluster(outside, inside);

    const r1 = analyzeTemporalCentroid(cluster);
    const r2 = analyzeRssiWeightedCentroid(cluster);

    const m1 = r1.metadata as Record<string, number>;
    const m2 = r2.metadata as Record<string, number>;
    expect(m2.outsideCentroidMs).toBeCloseTo(m1.outsideCentroidMs, 5);
    expect(m2.insideCentroidMs).toBeCloseTo(m1.insideCentroidMs, 5);
  });

  it("rssiTrendConsistencyFactor is 0.5 when all RSSI are null", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "null");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.rssiTrendConsistencyFactor).toBe(0.5);
  });

  it("confidence = Algorithm1 confidence × 0.5 when all RSSI are null", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "null");
    const cluster = makeCluster(outside, inside);

    const r1 = analyzeTemporalCentroid(cluster);
    const r2 = analyzeRssiWeightedCentroid(cluster);
    expect(r2.confidence).toBeCloseTo(r1.confidence * 0.5, 5);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — RSSI-weighted centroid position shifts
//
// Tests that the RSSI profile physically moves the centroid in the expected
// direction, which in turn affects centroidSeparationFactor.
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — centroid position shifts (RWO + RWI)", () => {
  /**
   * For the baseline temporal setup:
   *   TWO spans [BASE+0, BASE+2000], unweighted centroid at BASE+1000
   *   TWI spans [BASE+2000, BASE+4000], unweighted centroid at BASE+3000
   */

  it("falling outside RSSI pulls outside centroid EARLIER than unweighted", () => {
    // "falling" → early scans have higher weight → centroid shifts left
    const outsideFalling = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const outsideNull = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const dummyInside = makeWave(INSIDE_LH, TWI_CENTER, "null");

    const r_fall = analyzeRssiWeightedCentroid(
      makeCluster(outsideFalling, dummyInside),
    );
    const r_null = analyzeRssiWeightedCentroid(
      makeCluster(outsideNull, dummyInside),
    );

    const mFall = r_fall.metadata as Record<string, number>;
    const mNull = r_null.metadata as Record<string, number>;
    expect(mFall.outsideCentroidMs).toBeLessThan(mNull.outsideCentroidMs);
  });

  it("rising inside RSSI pulls inside centroid LATER than unweighted", () => {
    // "rising" → late scans have higher weight → centroid shifts right
    const dummyOutside = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const insideRising = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const insideNull = makeWave(INSIDE_LH, TWI_CENTER, "null");

    const r_rise = analyzeRssiWeightedCentroid(
      makeCluster(dummyOutside, insideRising),
    );
    const r_null = analyzeRssiWeightedCentroid(
      makeCluster(dummyOutside, insideNull),
    );

    const mRise = r_rise.metadata as Record<string, number>;
    const mNull = r_null.metadata as Record<string, number>;
    expect(mRise.insideCentroidMs).toBeGreaterThan(mNull.insideCentroidMs);
  });

  it("agreement profile increases centroid separation vs null RSSI", () => {
    // fall + rise → outside earlier, inside later → larger separation
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const outsideNull = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const insideNull = makeWave(INSIDE_LH, TWI_CENTER, "null");

    const rAgreement = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    const rNull = analyzeRssiWeightedCentroid(
      makeCluster(outsideNull, insideNull),
    );

    const mA = rAgreement.metadata as Record<string, number>;
    const mN = rNull.metadata as Record<string, number>;
    expect(mA.centroidDeltaMs).toBeGreaterThan(mN.centroidDeltaMs);
    expect(rAgreement.centroidSeparationFactor).toBeGreaterThan(
      rNull.centroidSeparationFactor,
    );
  });

  it("contradiction profile DECREASES centroid separation vs null RSSI", () => {
    // rise + fall → outside later, inside earlier → smaller separation
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "rising");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "falling");
    const outsideNull = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const insideNull = makeWave(INSIDE_LH, TWI_CENTER, "null");

    const rContradict = analyzeRssiWeightedCentroid(
      makeCluster(outside, inside),
    );
    const rNull = analyzeRssiWeightedCentroid(
      makeCluster(outsideNull, insideNull),
    );

    const mC = rContradict.metadata as Record<string, number>;
    const mN = rNull.metadata as Record<string, number>;
    expect(mC.centroidDeltaMs).toBeLessThan(mN.centroidDeltaMs);
    expect(rContradict.centroidSeparationFactor).toBeLessThan(
      rNull.centroidSeparationFactor,
    );
  });

  it("flat RSSI does not shift the centroid (uniform weights)", () => {
    const outsideFlat = makeWave(OUTSIDE_LH, TWO_CENTER, "flat");
    const outsideNull = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const dummyInside = makeWave(INSIDE_LH, TWI_CENTER, "null");

    const rFlat = analyzeRssiWeightedCentroid(
      makeCluster(outsideFlat, dummyInside),
    );
    const rNull = analyzeRssiWeightedCentroid(
      makeCluster(outsideNull, dummyInside),
    );

    const mF = rFlat.metadata as Record<string, number>;
    const mN = rNull.metadata as Record<string, number>;
    // Flat RSSI → weight=0.5 uniform → centroid unchanged
    expect(mF.outsideCentroidMs).toBeCloseTo(mN.outsideCentroidMs, 3);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — RSSI trend consistency factor: all five outcomes
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — rssiTrendConsistencyFactor outcomes", () => {
  /**
   * Use the baseline temporal setup (IN direction, large separation) so the
   * direction is unambiguously "in".  Only the RSSI profiles vary.
   *
   * For "in": outside expected slope < 0 (falling), inside expected slope > 0 (rising)
   */

  it("both agree (falling outside, rising inside) → factor = 1.0", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
  });

  it("one agree + one inconclusive (outside falls, inside flat) → factor = 0.7", () => {
    // flat RSSI → slope≈0, R²≈0 → inconclusive
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "flat");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(0.7);
  });

  it("one agree + one inconclusive (outside flat, inside rises) → factor = 0.7", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "flat");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(0.7);
  });

  it("one agree + one contradict (outside falls, inside falls) → factor = 0.4", () => {
    // inside "falling" contradicts the expected rising slope for "in"
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "falling");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    // Direction should still be "in" (temporal separation dominates)
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(0.4);
  });

  it("both contradict (outside rises, inside falls) → factor = CONFIDENCE_FACTOR_FLOOR", () => {
    // Both slopes contradict the expected profile for "in"
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "rising");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "falling");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(CONFIDENCE_FACTOR_FLOOR);
  });

  it("both inconclusive (flat/flat) → factor = 0.5 (neutral)", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "flat");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "flat");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.rssiTrendConsistencyFactor).toBe(0.5);
  });

  it("direction UNKNOWN → factor = 0.5 (null RSSI + identical temporal centres)", () => {
    // Null RSSI → all weights = 1.0 → weighted centroid = unweighted centroid.
    // Same temporal centre → equal centroids → "unknown".
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const inside = makeWave(INSIDE_LH, TWO_CENTER, "null");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("unknown");
    expect(r.rssiTrendConsistencyFactor).toBe(0.5);
  });

  it("agreeing RSSI can RESOLVE direction even with identical temporal centres", () => {
    // Algorithm 2 feature: falling outside RSSI pulls its centroid earlier;
    // rising inside RSSI pulls its centroid later.  Even when both temporal
    // waves are co-centred, the weighted centroids diverge → "in".
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWO_CENTER, "rising");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
  });

  it("fewer than 3 scans on outside → factor = 0.5", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling", HALF_WIDTH_MS, 2);
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.rssiTrendConsistencyFactor).toBe(0.5);
  });

  it("fewer than 3 scans on inside → factor = 0.5", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising", HALF_WIDTH_MS, 2);
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.rssiTrendConsistencyFactor).toBe(0.5);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — Symmetric RSSI outcomes for OUT direction
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — OUT direction RSSI symmetry", () => {
  /**
   * For "out": inside detects first.  Expected slopes:
   *   inside  slope < 0 (falling — person leaving inside, signal weakens)
   *   outside slope > 0 (rising  — person approaching outside, signal grows)
   */

  it("both agree for OUT (inside falls, outside rises) → factor = 1.0", () => {
    const inside = makeWave(INSIDE_LH, WAVE1_CENTER, "falling");
    const outside = makeWave(OUTSIDE_LH, SCENARIO_E_W2, "rising");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("out");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
  });

  it("both contradict for OUT (inside rises, outside falls) → factor = FLOOR", () => {
    const inside = makeWave(INSIDE_LH, WAVE1_CENTER, "rising");
    const outside = makeWave(OUTSIDE_LH, SCENARIO_E_W2, "falling");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    expect(r.direction).toBe("out");
    expect(r.rssiTrendConsistencyFactor).toBe(CONFIDENCE_FACTOR_FLOOR);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — Wave overlap scenarios — IN direction, RSSI agreeing
//
// Mirrors the A–F scenarios from temporal-centroid.test.ts but with a full
// set of agreeing RSSI waves on both sides (RWO="falling", RWI="rising").
//
// Because RSSI agreement also increases the centroid separation, the absolute
// confidence values differ from Algorithm 1, but the monotonic ordering holds.
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — wave scenarios (IN, RSSI agreeing)", () => {
  function inAgreeing(wave2CenterMs: number) {
    const outside = makeWave(OUTSIDE_LH, WAVE1_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, wave2CenterMs, "rising");
    return analyzeRssiWeightedCentroid(makeCluster(outside, inside));
  }

  it("(A) simultaneous temporal waves → RSSI alone resolves 'in', trend = 1.0", () => {
    // Temporal centroids are equal, but agreeing RSSI shifts them apart.
    // Unlike Algorithm 1, Algorithm 2 can determine direction here.
    const r = inAgreeing(WAVE1_CENTER);
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    // CSF is non-floor but small (driven by RSSI shift only, not temporal gap)
    expect(r.centroidSeparationFactor).toBeGreaterThan(CONFIDENCE_FACTOR_FLOOR);
    expect(r.confidence).toBeLessThan(0.4); // low overall (small separation)
  });

  it("(B) small separation → IN, very low confidence, trend = 1.0", () => {
    const r = inAgreeing(SCENARIO_B_W2);
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    // RSSI boosts CSF slightly above Algorithm 1's 0.2
    expect(r.centroidSeparationFactor).toBeGreaterThan(0.2);
    expect(r.confidence).toBeGreaterThan(0.2);
    expect(r.confidence).toBeLessThan(0.4); // still low overall
  });

  it("(C) medium separation → IN, mid confidence, trend = 1.0", () => {
    const r = inAgreeing(SCENARIO_C_W2);
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    expect(r.confidence).toBeGreaterThan(0.3);
  });

  it("(D) larger separation → IN, larger confidence, trend = 1.0", () => {
    const r = inAgreeing(SCENARIO_D_W2);
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    expect(r.confidence).toBeGreaterThan(inAgreeing(SCENARIO_C_W2).confidence);
  });

  it("(E) wave 2 starts as wave 1 ends → IN, large confidence, trend = 1.0", () => {
    const r = inAgreeing(SCENARIO_E_W2);
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    expect(r.confidence).toBeGreaterThan(0.5);
  });

  it("(F) clear gap between waves → IN, very large confidence, trend = 1.0", () => {
    const r = inAgreeing(SCENARIO_F_W2);
    expect(r.direction).toBe("in");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    expect(r.confidence).toBeGreaterThan(inAgreeing(SCENARIO_E_W2).confidence);
  });

  it.todo(
    "(G) extreme gap → orphaned scans (tested in event-sweeper suite)",
  );

  it("confidence increases monotonically from B through F (IN, RSSI agreeing)", () => {
    const confs = [
      SCENARIO_B_W2,
      SCENARIO_C_W2,
      SCENARIO_D_W2,
      SCENARIO_E_W2,
      SCENARIO_F_W2,
    ].map((c) => inAgreeing(c).confidence);

    for (let i = 1; i < confs.length; i++) {
      expect(confs[i]).toBeGreaterThan(confs[i - 1]!);
    }
  });

  it("all B–F scenarios produce direction IN with trend = 1.0", () => {
    for (const c of [
      SCENARIO_B_W2,
      SCENARIO_C_W2,
      SCENARIO_D_W2,
      SCENARIO_E_W2,
      SCENARIO_F_W2,
    ]) {
      const r = inAgreeing(c);
      expect(r.direction).toBe("in");
      expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 7 — Wave overlap scenarios — OUT direction, RSSI agreeing
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — wave scenarios (OUT, RSSI agreeing)", () => {
  function outAgreeing(wave2CenterMs: number) {
    // Inside fires first (wave 1), outside fires later (wave 2)
    // For OUT agreement: inside falls, outside rises
    const inside = makeWave(INSIDE_LH, WAVE1_CENTER, "falling");
    const outside = makeWave(OUTSIDE_LH, wave2CenterMs, "rising");
    return analyzeRssiWeightedCentroid(makeCluster(outside, inside));
  }

  it("(A) simultaneous temporal waves → RSSI alone resolves 'out', trend = 1.0", () => {
    // Matching the IN scenario: inside(falling) earlier centroid, outside(rising) later.
    const r = outAgreeing(WAVE1_CENTER);
    expect(r.direction).toBe("out");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
  });

  it("(B) small separation → OUT, very low confidence", () => {
    const r = outAgreeing(SCENARIO_B_W2);
    expect(r.direction).toBe("out");
    expect(r.rssiTrendConsistencyFactor).toBe(1.0);
    expect(r.confidence).toBeLessThan(0.4);
  });

  it("(C) medium separation → OUT, mid confidence", () => {
    const r = outAgreeing(SCENARIO_C_W2);
    expect(r.direction).toBe("out");
    expect(r.confidence).toBeGreaterThan(outAgreeing(SCENARIO_B_W2).confidence);
  });

  it("(D) larger separation → OUT, increasing confidence", () => {
    const r = outAgreeing(SCENARIO_D_W2);
    expect(r.direction).toBe("out");
    expect(r.confidence).toBeGreaterThan(outAgreeing(SCENARIO_C_W2).confidence);
  });

  it("(E) wave 2 starts as wave 1 ends → OUT, large confidence", () => {
    const r = outAgreeing(SCENARIO_E_W2);
    expect(r.direction).toBe("out");
    expect(r.confidence).toBeGreaterThan(0.5);
  });

  it("(F) clear gap → OUT, very large confidence", () => {
    const r = outAgreeing(SCENARIO_F_W2);
    expect(r.direction).toBe("out");
    expect(r.confidence).toBeGreaterThan(outAgreeing(SCENARIO_E_W2).confidence);
  });

  it.todo("(G) extreme gap → orphaned scans (event-sweeper suite)");

  it("confidence increases monotonically B → F (OUT, RSSI agreeing)", () => {
    const confs = [
      SCENARIO_B_W2,
      SCENARIO_C_W2,
      SCENARIO_D_W2,
      SCENARIO_E_W2,
      SCENARIO_F_W2,
    ].map((c) => outAgreeing(c).confidence);

    for (let i = 1; i < confs.length; i++) {
      expect(confs[i]).toBeGreaterThan(confs[i - 1]!);
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 8 — Confidence ordering across all RSSI configurations
//
// Fixed temporal setup (baseline IN, scenario E-level).
// Varying the 4 RSSI waves produces a predictable confidence ordering.
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — RSSI configuration confidence ordering", () => {
  function withProfiles(rwo: RssiProfile, rwi: RssiProfile) {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, rwo);
    const inside = makeWave(INSIDE_LH, TWI_CENTER, rwi);
    return analyzeRssiWeightedCentroid(makeCluster(outside, inside));
  }

  it("full agreement > one-agree-one-inconclusive > one-agree-one-contradict > both-contradict", () => {
    const agree = withProfiles("falling", "rising");
    const halfAgree = withProfiles("falling", "flat");
    const oneContradict = withProfiles("falling", "falling");
    const bothContradict = withProfiles("rising", "falling");

    expect(agree.confidence).toBeGreaterThan(halfAgree.confidence);
    expect(halfAgree.confidence).toBeGreaterThan(oneContradict.confidence);
    expect(oneContradict.confidence).toBeGreaterThan(bothContradict.confidence);
  });

  it("agreement boosts Algorithm 2 confidence above Algorithm 1", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const cluster = makeCluster(outside, inside);

    const r1 = analyzeTemporalCentroid(cluster);
    const r2 = analyzeRssiWeightedCentroid(cluster);

    // Algo2: larger CSF (RSSI pulls centroids apart) × trend=1.0 > Algo1
    expect(r2.confidence).toBeGreaterThan(r1.confidence);
  });

  it("both-contradict collapses Algorithm 2 confidence far below Algorithm 1", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "rising");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "falling");
    const cluster = makeCluster(outside, inside);

    const r1 = analyzeTemporalCentroid(cluster);
    const r2 = analyzeRssiWeightedCentroid(cluster);

    // Algo2: smaller CSF (RSSI pulls centroids together) × trend=FLOOR << Algo1
    expect(r2.confidence).toBeLessThan(r1.confidence);
    expect(r2.confidence).toBeLessThan(0.1);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 9 — RSSI regression properties
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — RSSI regression properties", () => {
  it("perfectly linear RSSI profile produces R² = 1.0", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    const trend = (r.metadata as Record<string, Record<string, Record<string, number>>>).rssiTrend;
    expect(trend.outside.r2).toBeCloseTo(1.0, 5);
    expect(trend.inside.r2).toBeCloseTo(1.0, 5);
  });

  it("flat RSSI profile produces R² ≈ 0 (no variance to explain)", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "flat");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "flat");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    const trend = (r.metadata as Record<string, Record<string, Record<string, number>>>).rssiTrend;
    expect(trend.outside.r2).toBeCloseTo(0.0, 5);
    expect(trend.inside.r2).toBeCloseTo(0.0, 5);
  });

  it("falling outside RSSI has negative slope", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "falling");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "null");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    const trend = (r.metadata as Record<string, Record<string, Record<string, number>>>).rssiTrend;
    expect(trend.outside.slope).toBeLessThan(0);
  });

  it("rising inside RSSI has positive slope", () => {
    const outside = makeWave(OUTSIDE_LH, TWO_CENTER, "null");
    const inside = makeWave(INSIDE_LH, TWI_CENTER, "rising");
    const r = analyzeRssiWeightedCentroid(makeCluster(outside, inside));
    const trend = (r.metadata as Record<string, Record<string, Record<string, number>>>).rssiTrend;
    expect(trend.inside.slope).toBeGreaterThan(0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 10 — IN/OUT direction symmetry with RSSI
// ─────────────────────────────────────────────────────────────────────────────

describe("analyzeRssiWeightedCentroid — IN/OUT symmetry with RSSI", () => {
  it("swapping inside/outside (with matched RSSI profiles) flips direction, preserves confidence", () => {
    // IN: outside(falling) fires first, inside(rising) fires second
    const outsideIn = makeWave(OUTSIDE_LH, WAVE1_CENTER, "falling");
    const insideIn = makeWave(INSIDE_LH, SCENARIO_D_W2, "rising");
    const rIn = analyzeRssiWeightedCentroid(makeCluster(outsideIn, insideIn));

    // OUT: inside(falling) fires first, outside(rising) fires second
    // Reassign lighthouse IDs to match the swapped roles
    const insideOut: ScanData[] = makeWave(
      INSIDE_LH,
      WAVE1_CENTER,
      "falling",
    ).map((s) => ({ ...s, lighthouseId: INSIDE_LH }));
    const outsideOut: ScanData[] = makeWave(
      OUTSIDE_LH,
      SCENARIO_D_W2,
      "rising",
    ).map((s) => ({ ...s, lighthouseId: OUTSIDE_LH }));
    const rOut = analyzeRssiWeightedCentroid(
      makeCluster(outsideOut, insideOut),
    );

    expect(rIn.direction).toBe("in");
    expect(rOut.direction).toBe("out");
    // Confidence should be identical (same physical separation, same RSSI profiles)
    expect(rIn.confidence).toBeCloseTo(rOut.confidence, 10);
    expect(rIn.rssiTrendConsistencyFactor).toBe(
      rOut.rssiTrendConsistencyFactor,
    );
  });
});
