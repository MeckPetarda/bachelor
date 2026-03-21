/**
 * Tests for src/services/algorithms/temporal-centroid.ts
 *
 * These are pure unit tests - no database, no MQTT, no async.
 *
 * -- Wave model ----------------------------------------------------------------
 *
 * A person walking through a doorway produces two overlapping "waves" of RFID
 * detections.  One lighthouse starts detecting first (wave 1), builds to a peak,
 * then decays.  The other lighthouse (wave 2) starts at a variable offset.
 *
 * When the temporal gap between the waves grows the algorithm can more
 * confidently determine which side was entered from. Six overlap scenarios are
 * tested (A-F), plus a scenario G placeholder for orphan logic (future).
 *
 *   A  waves start simultaneously           -> unknown direction, floor confidence
 *   B  wave 2 slightly after wave 1 rises   -> very low confidence
 *   C  wave 2 starts at wave 1 peak         -> mid confidence
 *   D  wave 2 starts as wave 1 declines     -> larger confidence
 *   E  wave 2 starts as wave 1 just ends    -> large confidence
 *   F  wave 2 starts well after wave 1 ends -> very large confidence
 *   G  (orphan scenario - not yet testable, structural placeholder only)
 *
 * Every A-F scenario is tested for both traversal directions (IN and OUT).
 */

import { describe, it, expect } from "bun:test";
import { analyzeTemporalCentroid } from "../src/services/algorithms/temporal-centroid";
import {
  CONFIDENCE_FACTOR_FLOOR,
  type ScanData,
  type PartitionedCluster,
} from "../src/services/algorithms/types";

// --- Constants ----------------------------------------------------------------

const BASE_TIME = new Date("2025-01-01T00:00:00Z").getTime();

const OUTSIDE_LH_ID = 1;
const INSIDE_LH_ID = 2;
const EPC = "ETEST_WAVE_0000001";
const GROUP_ID = 1;

/**
 * Wave parameters shared across all scenarios.
 *
 * Each wave spans [center - HALF_WIDTH, center + HALF_WIDTH] and contains
 * SCANS_PER_WAVE timestamps evenly distributed, so:
 *   - centroid == center (exactly)
 *   - wave duration == 2 * HALF_WIDTH
 */
const HALF_WIDTH_MS = 1000; // +/-1 000 ms around each peak
const SCANS_PER_WAVE = 20; // enough to saturate clusterSizeFactor

// --- Helper: build a wave of ScanData ----------------------------------------

let _idCounter = BigInt(1);
function nextId(): bigint {
  return _idCounter++;
}

/**
 * Generate `count` ScanData entries whose timestamps are uniformly spread
 * over [baseTime + centerMs - halfWidthMs, baseTime + centerMs + halfWidthMs].
 *
 * Because the distribution is perfectly symmetric, the arithmetic mean
 * (centroid) equals exactly baseTime + centerMs.
 */
function makeWave(
  lighthouseId: number,
  centerMs: number,
  halfWidthMs: number = HALF_WIDTH_MS,
  count: number = SCANS_PER_WAVE,
): ScanData[] {
  const scans: ScanData[] = [];
  for (let i = 0; i < count; i++) {
    // Map i in [0, count-1] to t in [-1, 1], then scale by halfWidth
    const t = count === 1 ? 0 : (i / (count - 1)) * 2 - 1;
    scans.push({
      id: nextId(),
      lighthouseId,
      epc: EPC,
      rssiDbm: null,
      timestamp: new Date(BASE_TIME + centerMs + t * halfWidthMs),
      timeBasis: "synced",
    });
  }
  return scans;
}

/**
 * Build a PartitionedCluster from outside and inside scan arrays.
 * clusterStartedAt / clusterEndedAt are derived from the combined scan set.
 */
function makeCluster(
  outsideScans: ScanData[],
  insideScans: ScanData[],
): PartitionedCluster {
  const allScans = [...outsideScans, ...insideScans];
  const times = allScans.map((s) => s.timestamp.getTime());
  return {
    epc: EPC,
    groupId: GROUP_ID,
    outsideScans,
    insideScans,
    allScans,
    clusterStartedAt: new Date(Math.min(...times)),
    clusterEndedAt: new Date(Math.max(...times)),
  };
}

// --- Wave scenario centres (ms offset from BASE_TIME) -------------------------
//
// Wave 1 is always centred at WAVE1_CENTER.  Wave 2 is centred at offsets that
// produce progressively less overlap with wave 1.
//
// Wave 1 spans [WAVE1_CENTER - HALF_WIDTH, WAVE1_CENTER + HALF_WIDTH]
//              = [0, 2000] ms
//
// Scenario offsets chosen so that:
//   B -> wave 2 starts rising while wave 1 is still rising   (overlap = 75%)
//   C -> wave 2 starts at wave 1's peak                      (overlap = 50%)
//   D -> wave 2 starts while wave 1 is descending            (overlap = 25%)
//   E -> wave 2 starts exactly as wave 1 ends                (overlap = 0%)
//   F -> wave 2 starts clearly after wave 1 has ended        (gap > 0)

const WAVE1_CENTER = 1000; // ms from BASE_TIME

const SCENARIO_B_W2 = 1500; // wave 2 centre 500 ms after wave 1 centre
const SCENARIO_C_W2 = 2000; // wave 2 centre 1 000 ms after wave 1 centre
const SCENARIO_D_W2 = 2500; // wave 2 centre 1 500 ms after wave 1 centre
const SCENARIO_E_W2 = 3000; // wave 2 centre 2 000 ms after wave 1 centre (just touching)
const SCENARIO_F_W2 = 4000; // wave 2 centre 3 000 ms after wave 1 centre (clear gap)

// -----------------------------------------------------------------------------
// Expected confidence values (derived analytically)
//
// centroidSeparationFactor = centroidDelta / clusterDuration
//   where clusterDuration = (max timestamp of all scans) - (min timestamp of all scans)
//
// Wave 1 spans  [W1C - HW, W1C + HW] = [0, 2000]
// Wave 2 spans  [W2C - HW, W2C + HW]
// clusterDuration = (W2C + HW) - 0 = W2C + HW
//
//   B: delta=500,  duration=2500  -> CSF=500/2500   = 0.200
//   C: delta=1000, duration=3000  -> CSF=1000/3000  ~ 0.333
//   D: delta=1500, duration=3500  -> CSF=1500/3500  ~ 0.429
//   E: delta=2000, duration=4000  -> CSF=2000/4000  = 0.500
//   F: delta=3000, duration=5000  -> CSF=3000/5000  = 0.600
//
// clusterSizeFactor  = min(1.0, (40 - 2) / 8) = 1.0   (40 total scans)
// bilateralCoverage  = 20/20 = 1.0
//
// => confidence == CSF for all B-F scenarios.
// -----------------------------------------------------------------------------

// ===============================================================================
// SECTION 1 - Core direction detection
// ===============================================================================

describe("analyzeTemporalCentroid - core direction detection", () => {
  it("outside scans earlier than inside -> direction IN", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    const result = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(result.direction).toBe("in");
  });

  it("inside scans earlier than outside -> direction OUT", () => {
    const inside = makeWave(INSIDE_LH_ID, 0);
    const outside = makeWave(OUTSIDE_LH_ID, 2000);
    const result = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(result.direction).toBe("out");
  });

  it("identical centroids -> direction UNKNOWN", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 1000);
    const inside = makeWave(INSIDE_LH_ID, 1000);
    const result = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(result.direction).toBe("unknown");
  });

  it("centroid delta <= 1 ms -> direction UNKNOWN", () => {
    // outside centroid at 1000 ms, inside centroid at 1000.5 ms (1 ms apart)
    const outside = makeWave(OUTSIDE_LH_ID, 1000, 0, 1); // single scan
    const inside = makeWave(INSIDE_LH_ID, 1001, 0, 1); // single scan 1 ms later
    const result = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(result.direction).toBe("unknown");
  });

  it("canonical timestamp is outside centroid for IN", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 500);
    const inside = makeWave(INSIDE_LH_ID, 2500);
    const result = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(result.direction).toBe("in");
    // Outside centroid is at BASE_TIME + 500
    expect(result.timestamp.getTime()).toBeCloseTo(BASE_TIME + 500, -1);
  });

  it("canonical timestamp is inside centroid for OUT", () => {
    const inside = makeWave(INSIDE_LH_ID, 500);
    const outside = makeWave(OUTSIDE_LH_ID, 2500);
    const result = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(result.direction).toBe("out");
    // Inside centroid is at BASE_TIME + 500
    expect(result.timestamp.getTime()).toBeCloseTo(BASE_TIME + 500, -1);
  });

  it("canonical timestamp is midpoint for UNKNOWN", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 1000);
    const inside = makeWave(INSIDE_LH_ID, 1000);
    const result = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(result.direction).toBe("unknown");
    expect(result.timestamp.getTime()).toBeCloseTo(BASE_TIME + 1000, -1);
  });
});

// ===============================================================================
// SECTION 2 - Confidence factor invariants
// ===============================================================================

describe("analyzeTemporalCentroid - confidence factor invariants", () => {
  it("all factors are >= CONFIDENCE_FACTOR_FLOOR", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(r.centroidSeparationFactor).toBeGreaterThanOrEqual(
      CONFIDENCE_FACTOR_FLOOR,
    );
    expect(r.clusterSizeFactor).toBeGreaterThanOrEqual(CONFIDENCE_FACTOR_FLOOR);
    expect(r.bilateralCoverageFactor).toBeGreaterThanOrEqual(
      CONFIDENCE_FACTOR_FLOOR,
    );
    expect(r.confidence).toBeGreaterThanOrEqual(CONFIDENCE_FACTOR_FLOOR ** 3);
  });

  it("all factors are <= 1.0", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(r.centroidSeparationFactor).toBeLessThanOrEqual(1.0);
    expect(r.clusterSizeFactor).toBeLessThanOrEqual(1.0);
    expect(r.bilateralCoverageFactor).toBeLessThanOrEqual(1.0);
    expect(r.confidence).toBeLessThanOrEqual(1.0);
  });

  it("rssiTrendConsistencyFactor is null", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(r.rssiTrendConsistencyFactor).toBeNull();
  });

  it("confidence is the product of the three factors", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(r.confidence).toBeCloseTo(
      r.centroidSeparationFactor *
        r.clusterSizeFactor *
        r.bilateralCoverageFactor,
      10,
    );
  });

  it("clusterSizeFactor = FLOOR when only 2 total scans (minimum)", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0, 0, 1);
    const inside = makeWave(INSIDE_LH_ID, 2000, 0, 1);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    // (2 - 2) / 8 = 0 -> clamped to floor
    expect(r.clusterSizeFactor).toBe(CONFIDENCE_FACTOR_FLOOR);
  });

  it("clusterSizeFactor saturates at 1.0 with >= 10 scans", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0, HALF_WIDTH_MS, 10);
    const inside = makeWave(INSIDE_LH_ID, 2000, HALF_WIDTH_MS, 10);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    // (20 - 2) / 8 = 2.25 -> clamped to 1.0
    expect(r.clusterSizeFactor).toBe(1.0);
  });

  it("bilateralCoverageFactor = 1.0 for a perfectly balanced cluster", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    // both waves have SCANS_PER_WAVE entries
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(r.bilateralCoverageFactor).toBe(1.0);
  });

  it("bilateralCoverageFactor < 1.0 for an unbalanced cluster", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0, HALF_WIDTH_MS, 20);
    const inside = makeWave(INSIDE_LH_ID, 2000, HALF_WIDTH_MS, 4); // 4 vs 20
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    // min(4,20)/max(4,20) = 0.2
    expect(r.bilateralCoverageFactor).toBeCloseTo(0.2, 5);
  });

  it("centroidSeparationFactor = FLOOR when clusterDuration = 0", () => {
    // Single scan per side at identical timestamp
    const t = new Date(BASE_TIME + 1000);
    const outside: ScanData[] = [
      {
        id: nextId(),
        lighthouseId: OUTSIDE_LH_ID,
        epc: EPC,
        rssiDbm: null,
        timestamp: t,
        timeBasis: "synced",
      },
    ];
    const inside: ScanData[] = [
      {
        id: nextId(),
        lighthouseId: INSIDE_LH_ID,
        epc: EPC,
        rssiDbm: null,
        timestamp: t,
        timeBasis: "synced",
      },
    ];
    // Force clusterDuration = 0 by making start == end
    const cluster: PartitionedCluster = {
      epc: EPC,
      groupId: GROUP_ID,
      outsideScans: outside,
      insideScans: inside,
      allScans: [...outside, ...inside],
      clusterStartedAt: t,
      clusterEndedAt: t,
    };
    const r = analyzeTemporalCentroid(cluster);
    expect(r.centroidSeparationFactor).toBe(CONFIDENCE_FACTOR_FLOOR);
  });
});

// ===============================================================================
// SECTION 3 - Metadata completeness
// ===============================================================================

describe("analyzeTemporalCentroid - metadata", () => {
  it("metadata contains all required keys with correct types", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    const m = r.metadata as Record<string, unknown>;
    expect(typeof m.outsideCentroidMs).toBe("number");
    expect(typeof m.insideCentroidMs).toBe("number");
    expect(typeof m.centroidDeltaMs).toBe("number");
    expect(typeof m.clusterDurationMs).toBe("number");
    expect(typeof m.outsideScanCount).toBe("number");
    expect(typeof m.insideScanCount).toBe("number");
  });

  it("metadata scanCounts match actual scan array lengths", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0, HALF_WIDTH_MS, 12);
    const inside = makeWave(INSIDE_LH_ID, 2000, HALF_WIDTH_MS, 8);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    const m = r.metadata as Record<string, number>;
    expect(m.outsideScanCount).toBe(12);
    expect(m.insideScanCount).toBe(8);
  });

  it("metadata centroidDeltaMs equals |outside - inside|", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 500, 0, 1); // single scan -> centroid = 500
    const inside = makeWave(INSIDE_LH_ID, 1800, 0, 1); // single scan -> centroid = 1800
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    const m = r.metadata as Record<string, number>;
    expect(m.centroidDeltaMs).toBeCloseTo(1300, 5);
  });

  it("algorithmId is 'temporal_centroid'", () => {
    const outside = makeWave(OUTSIDE_LH_ID, 0);
    const inside = makeWave(INSIDE_LH_ID, 2000);
    const r = analyzeTemporalCentroid(makeCluster(outside, inside));
    expect(r.algorithmId).toBe("temporal_centroid");
  });
});

// ===============================================================================
// SECTION 4 - Wave overlap scenarios - IN direction
//
// In the IN direction: person approaches from outside -> outside wave fires first,
// then inside wave fires as they cross the threshold.
//
// outside = wave 1 (always centred at WAVE1_CENTER)
// inside  = wave 2 (centred at varying offsets)
// ===============================================================================

describe("analyzeTemporalCentroid - wave scenarios (IN direction)", () => {
  // -- Helper ----------------------------------------------------------------
  function inScenario(wave2CenterMs: number) {
    const outside = makeWave(OUTSIDE_LH_ID, WAVE1_CENTER);
    const inside = makeWave(INSIDE_LH_ID, wave2CenterMs);
    return analyzeTemporalCentroid(makeCluster(outside, inside));
  }

  // -- Scenario A - simultaneous waves --------------------------------------
  it("(A) simultaneous waves -> direction UNKNOWN, confidence at floor", () => {
    const r = inScenario(WAVE1_CENTER); // both centred at same point
    expect(r.direction).toBe("unknown");
    // centroidDelta = 0 -> centroidSeparationFactor = FLOOR
    expect(r.centroidSeparationFactor).toBe(CONFIDENCE_FACTOR_FLOOR);
  });

  // -- Scenario B - wave 2 slightly after wave 1 starts rising --------------
  it("(B) very small temporal separation -> direction IN, very low confidence", () => {
    const r = inScenario(SCENARIO_B_W2);
    expect(r.direction).toBe("in");
    // Expected: CSF = 500/2500 = 0.200
    expect(r.centroidSeparationFactor).toBeCloseTo(0.2, 5);
    expect(r.confidence).toBeCloseTo(0.2, 5); // CSF * 1.0 * 1.0
    expect(r.confidence).toBeLessThan(0.25); // "very low"
  });

  // -- Scenario C - wave 2 starts at wave 1's peak ---------------------------
  it("(C) wave 2 starts at wave 1 peak -> direction IN, mid confidence", () => {
    const r = inScenario(SCENARIO_C_W2);
    expect(r.direction).toBe("in");
    // Expected: CSF = 1000/3000 ~ 0.333
    expect(r.centroidSeparationFactor).toBeCloseTo(1 / 3, 5);
    expect(r.confidence).toBeCloseTo(1 / 3, 5);
    expect(r.confidence).toBeGreaterThan(0.25); // higher than B
    expect(r.confidence).toBeLessThan(0.4); // still "mid"
  });

  // -- Scenario D - wave 2 starts as wave 1 is declining --------------------
  it("(D) wave 2 starts in wave 1 decay -> direction IN, larger confidence", () => {
    const r = inScenario(SCENARIO_D_W2);
    expect(r.direction).toBe("in");
    // Expected: CSF = 1500/3500 ~ 0.429
    expect(r.centroidSeparationFactor).toBeCloseTo(1500 / 3500, 5);
    expect(r.confidence).toBeCloseTo(1500 / 3500, 5);
    expect(r.confidence).toBeGreaterThan(1 / 3); // higher than C
    expect(r.confidence).toBeLessThan(0.48);
  });

  // -- Scenario E - wave 2 starts just as wave 1 finishes -------------------
  it("(E) wave 2 starts as wave 1 ends -> direction IN, large confidence", () => {
    const r = inScenario(SCENARIO_E_W2);
    expect(r.direction).toBe("in");
    // Expected: CSF = 2000/4000 = 0.500
    expect(r.centroidSeparationFactor).toBeCloseTo(0.5, 5);
    expect(r.confidence).toBeCloseTo(0.5, 5);
    expect(r.confidence).toBeGreaterThan(1500 / 3500); // higher than D
  });

  // -- Scenario F - wave 2 starts well after wave 1 has ended ---------------
  it("(F) clear temporal gap between waves -> direction IN, very large confidence", () => {
    const r = inScenario(SCENARIO_F_W2);
    expect(r.direction).toBe("in");
    // Expected: CSF = 3000/5000 = 0.600
    expect(r.centroidSeparationFactor).toBeCloseTo(0.6, 5);
    expect(r.confidence).toBeCloseTo(0.6, 5);
    expect(r.confidence).toBeGreaterThan(0.5); // higher than E
  });

  // -- Scenario G - structural placeholder ----------------------------------
  it.todo(
    "(G) extremely large gap between waves -> orphaned scans (tested in event-sweeper suite)",
  );

  // -- Monotonic ordering ----------------------------------------------------
  it("confidence increases monotonically from scenario B through F", () => {
    const rB = inScenario(SCENARIO_B_W2);
    const rC = inScenario(SCENARIO_C_W2);
    const rD = inScenario(SCENARIO_D_W2);
    const rE = inScenario(SCENARIO_E_W2);
    const rF = inScenario(SCENARIO_F_W2);

    expect(rB.confidence).toBeLessThan(rC.confidence);
    expect(rC.confidence).toBeLessThan(rD.confidence);
    expect(rD.confidence).toBeLessThan(rE.confidence);
    expect(rE.confidence).toBeLessThan(rF.confidence);
  });

  it("all IN scenarios B-F produce direction IN", () => {
    for (const center of [
      SCENARIO_B_W2,
      SCENARIO_C_W2,
      SCENARIO_D_W2,
      SCENARIO_E_W2,
      SCENARIO_F_W2,
    ]) {
      expect(inScenario(center).direction).toBe("in");
    }
  });
});

// ===============================================================================
// SECTION 5 - Wave overlap scenarios - OUT direction
//
// In the OUT direction: person approaches from inside -> inside wave fires first,
// then outside wave fires as they exit.
//
// inside  = wave 1 (always centred at WAVE1_CENTER)
// outside = wave 2 (centred at varying offsets)
// ===============================================================================

describe("analyzeTemporalCentroid - wave scenarios (OUT direction)", () => {
  // -- Helper ----------------------------------------------------------------
  function outScenario(wave2CenterMs: number) {
    // Inside fires first (wave 1), outside fires later (wave 2)
    const inside = makeWave(INSIDE_LH_ID, WAVE1_CENTER);
    const outside = makeWave(OUTSIDE_LH_ID, wave2CenterMs);
    return analyzeTemporalCentroid(makeCluster(outside, inside));
  }

  // -- Scenario A ------------------------------------------------------------
  it("(A) simultaneous waves -> direction UNKNOWN", () => {
    const r = outScenario(WAVE1_CENTER);
    expect(r.direction).toBe("unknown");
    expect(r.centroidSeparationFactor).toBe(CONFIDENCE_FACTOR_FLOOR);
  });

  // -- Scenario B ------------------------------------------------------------
  it("(B) very small temporal separation -> direction OUT, very low confidence", () => {
    const r = outScenario(SCENARIO_B_W2);
    expect(r.direction).toBe("out");
    expect(r.centroidSeparationFactor).toBeCloseTo(0.2, 5);
    expect(r.confidence).toBeLessThan(0.25);
  });

  // -- Scenario C ------------------------------------------------------------
  it("(C) wave 2 starts at wave 1 peak -> direction OUT, mid confidence", () => {
    const r = outScenario(SCENARIO_C_W2);
    expect(r.direction).toBe("out");
    expect(r.centroidSeparationFactor).toBeCloseTo(1 / 3, 5);
    expect(r.confidence).toBeGreaterThan(0.25);
    expect(r.confidence).toBeLessThan(0.4);
  });

  // -- Scenario D ------------------------------------------------------------
  it("(D) wave 2 starts in wave 1 decay -> direction OUT, larger confidence", () => {
    const r = outScenario(SCENARIO_D_W2);
    expect(r.direction).toBe("out");
    expect(r.centroidSeparationFactor).toBeCloseTo(1500 / 3500, 5);
    expect(r.confidence).toBeGreaterThan(1 / 3);
  });

  // -- Scenario E ------------------------------------------------------------
  it("(E) wave 2 starts as wave 1 ends -> direction OUT, large confidence", () => {
    const r = outScenario(SCENARIO_E_W2);
    expect(r.direction).toBe("out");
    expect(r.centroidSeparationFactor).toBeCloseTo(0.5, 5);
    expect(r.confidence).toBeCloseTo(0.5, 5);
  });

  // -- Scenario F ------------------------------------------------------------
  it("(F) clear temporal gap -> direction OUT, very large confidence", () => {
    const r = outScenario(SCENARIO_F_W2);
    expect(r.direction).toBe("out");
    expect(r.centroidSeparationFactor).toBeCloseTo(0.6, 5);
    expect(r.confidence).toBeCloseTo(0.6, 5);
    expect(r.confidence).toBeGreaterThan(0.5);
  });

  // -- Scenario G - structural placeholder ----------------------------------
  it.todo(
    "(G) extremely large gap between waves -> orphaned scans (tested in event-sweeper suite)",
  );

  // -- Monotonic ordering ----------------------------------------------------
  it("confidence increases monotonically from scenario B through F (OUT)", () => {
    const rB = outScenario(SCENARIO_B_W2);
    const rC = outScenario(SCENARIO_C_W2);
    const rD = outScenario(SCENARIO_D_W2);
    const rE = outScenario(SCENARIO_E_W2);
    const rF = outScenario(SCENARIO_F_W2);

    expect(rB.confidence).toBeLessThan(rC.confidence);
    expect(rC.confidence).toBeLessThan(rD.confidence);
    expect(rD.confidence).toBeLessThan(rE.confidence);
    expect(rE.confidence).toBeLessThan(rF.confidence);
  });

  it("all OUT scenarios B-F produce direction OUT", () => {
    for (const center of [
      SCENARIO_B_W2,
      SCENARIO_C_W2,
      SCENARIO_D_W2,
      SCENARIO_E_W2,
      SCENARIO_F_W2,
    ]) {
      expect(outScenario(center).direction).toBe("out");
    }
  });
});

// ===============================================================================
// SECTION 6 - Direction symmetry
//
// Swapping which lighthouse is "inside" vs "outside" should flip the direction
// but produce identical confidence.
// ===============================================================================

describe("analyzeTemporalCentroid - IN/OUT symmetry", () => {
  it("swapping inside/outside yields opposite direction with equal confidence", () => {
    const wave1 = makeWave(OUTSIDE_LH_ID, WAVE1_CENTER);
    const wave2 = makeWave(INSIDE_LH_ID, SCENARIO_D_W2);

    // IN: outside fires first
    const rIn = analyzeTemporalCentroid(makeCluster(wave1, wave2));

    // OUT: inside fires first (swap the lighthouseId roles by swapping arrays)
    const wave1Out: ScanData[] = wave1.map((s) => ({
      ...s,
      lighthouseId: INSIDE_LH_ID,
    }));
    const wave2Out: ScanData[] = wave2.map((s) => ({
      ...s,
      lighthouseId: OUTSIDE_LH_ID,
    }));
    const rOut = analyzeTemporalCentroid(makeCluster(wave2Out, wave1Out));

    expect(rIn.direction).toBe("in");
    expect(rOut.direction).toBe("out");
    expect(rIn.confidence).toBeCloseTo(rOut.confidence, 10);
  });
});
