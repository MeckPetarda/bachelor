import type { PartitionedCluster, AlgorithmResult, ScanData } from "./types";
import { CONFIDENCE_FACTOR_FLOOR } from "./types";

// ─── RSSI weighting ───────────────────────────────────────────────────────────

/**
 * Convert an RSSI reading to a centroid weight.
 *
 *   null    → 1.0  (no reading; treated as neutral full weight)
 *   -40 dBm → 1.0  (very strong)
 *   -90 dBm → 0.1  (very weak)
 *
 * Formula: clamp(1.0 − (|rssiDbm| − 40) / 50, 0.1, 1.0)
 */
function rssiWeight(rssiDbm: number | null): number {
  if (rssiDbm === null) return 1.0;
  return Math.max(0.1, Math.min(1.0, 1.0 - (Math.abs(rssiDbm) - 40) / 50));
}

/**
 * Compute the RSSI-weighted arithmetic mean of scan timestamps (Unix ms).
 */
function weightedCentroid(scans: ScanData[]): number {
  let sumW = 0;
  let sumTW = 0;
  for (const s of scans) {
    const w = rssiWeight(s.rssiDbm);
    sumW += w;
    sumTW += s.timestamp.getTime() * w;
  }
  return sumTW / sumW;
}

// ─── Linear regression ────────────────────────────────────────────────────────

interface Trend {
  slope: number; // dBm per ms (cluster-relative)
  r2: number; // coefficient of determination ∈ [0, 1]
}

/**
 * Ordinary least-squares linear regression on (x, y) pairs.
 * Returns slope and R² (clamped to [0, 1]).
 */
function linearRegression(pairs: Array<[number, number]>): Trend {
  const n = pairs.length;
  if (n < 2) return { slope: 0, r2: 0 };

  let sumX = 0,
    sumY = 0,
    sumXY = 0,
    sumXX = 0;
  for (const [x, y] of pairs) {
    sumX += x;
    sumY += y;
    sumXY += x * y;
    sumXX += x * x;
  }

  const denom = n * sumXX - sumX * sumX;
  if (denom === 0) return { slope: 0, r2: 0 };

  const slope = (n * sumXY - sumX * sumY) / denom;
  const intercept = (sumY - slope * sumX) / n;
  const meanY = sumY / n;

  let ssRes = 0;
  let ssTot = 0;
  for (const [x, y] of pairs) {
    ssRes += (y - (slope * x + intercept)) ** 2;
    ssTot += (y - meanY) ** 2;
  }

  const r2 = ssTot === 0 ? 0 : Math.max(0, Math.min(1, 1 - ssRes / ssTot));
  return { slope, r2 };
}

/**
 * Compute the linear trend of RSSI values over time for a set of scans.
 * x = scan timestamp relative to clusterStartedAt (ms)
 * y = rssiDbm
 *
 * Returns null when fewer than 3 scans have a non-null RSSI (can't fit a line).
 */
function computeTrend(scans: ScanData[], clusterStartMs: number): Trend | null {
  const pairs: Array<[number, number]> = [];
  for (const s of scans) {
    if (s.rssiDbm !== null) {
      pairs.push([s.timestamp.getTime() - clusterStartMs, s.rssiDbm]);
    }
  }
  if (pairs.length < 3) return null;
  return linearRegression(pairs);
}

// ─── Trend consistency scoring ────────────────────────────────────────────────

type TrendClass = "agree" | "inconclusive" | "contradict";

/**
 * Classify a single lighthouse's RSSI trend relative to the expected direction.
 *
 * A slope is "significant" when R² ≥ 0.1.  If R² < 0.1 the slope is treated
 * as inconclusive regardless of its sign.
 */
function classifyTrend(
  trend: Trend | null,
  /** true if we expect the RSSI to be declining (slope < 0) */
  expectedNegative: boolean,
): TrendClass {
  if (trend === null) return "inconclusive";
  if (trend.r2 < 0.1) return "inconclusive";
  const actuallyNegative = trend.slope < 0;
  return actuallyNegative === expectedNegative ? "agree" : "contradict";
}

/**
 * Combine the two lighthouse trend classifications into a single factor.
 *
 * | outside  | inside       | factor              |
 * |----------|--------------|---------------------|
 * | agree    | agree        | 1.0                 |
 * | agree    | inconclusive | 0.7                 |
 * | inconclusive | agree    | 0.7                 |
 * | agree    | contradict   | 0.4                 |
 * | contradict | agree      | 0.4                 |
 * | contradict | contradict | CONFIDENCE_FACTOR_FLOOR |
 * | anything else            | 0.5 (neutral)       |
 *
 * Also returns 0.5 when:
 *   - direction is "unknown"
 *   - either lighthouse contributed fewer than 3 scans (regression not reliable)
 */
function rssiConsistencyFactor(
  outsideTrend: Trend | null,
  insideTrend: Trend | null,
  direction: "in" | "out" | "unknown",
  outsideScanCount: number,
  insideScanCount: number,
): number {
  if (direction === "unknown") return 0.5;
  if (outsideScanCount < 3 || insideScanCount < 3) return 0.5;

  // "in"  → outside weakens (neg slope), inside strengthens (pos slope)
  // "out" → inside weakens  (neg slope), outside strengthens (pos slope)
  const outsideExpectedNeg = direction === "in";
  const insideExpectedNeg = direction === "out";

  const oc = classifyTrend(outsideTrend, outsideExpectedNeg);
  const ic = classifyTrend(insideTrend, insideExpectedNeg);

  if (oc === "agree" && ic === "agree") return 1.0;
  if (
    (oc === "agree" && ic === "inconclusive") ||
    (oc === "inconclusive" && ic === "agree")
  )
    return 0.7;
  if (
    (oc === "agree" && ic === "contradict") ||
    (oc === "contradict" && ic === "agree")
  )
    return 0.4;
  if (oc === "contradict" && ic === "contradict") return CONFIDENCE_FACTOR_FLOOR;

  // Both inconclusive, or one contradict + one inconclusive → neutral
  return 0.5;
}

// ─── Main algorithm ───────────────────────────────────────────────────────────

/** Clamp to [CONFIDENCE_FACTOR_FLOOR, 1.0]. */
function clamp(value: number): number {
  return Math.max(CONFIDENCE_FACTOR_FLOOR, Math.min(1.0, value));
}

/**
 * Algorithm 2 — RSSI-Weighted Centroid + Trend.
 *
 * Pure function: no DB access, no side effects.
 *
 * Extends Algorithm 1 by:
 *   1. Using RSSI-weighted centroids instead of arithmetic means.
 *   2. Running a linear regression on RSSI-vs-time per lighthouse and
 *      multiplying in an `rssiTrendConsistencyFactor`.
 *
 * Confidence = centroidSeparationFactor × clusterSizeFactor
 *            × bilateralCoverageFactor × rssiTrendConsistencyFactor
 */
export function analyzeRssiWeightedCentroid(
  cluster: PartitionedCluster,
): AlgorithmResult {
  const { insideScans, outsideScans, clusterStartedAt, clusterEndedAt } =
    cluster;

  const clusterStartMs = clusterStartedAt.getTime();
  const clusterDurationMs = clusterEndedAt.getTime() - clusterStartMs;

  // ── Weighted centroids ─────────────────────────────────────────────────────

  const outsideCentroidMs = weightedCentroid(outsideScans);
  const insideCentroidMs = weightedCentroid(insideScans);
  const centroidDeltaMs = Math.abs(outsideCentroidMs - insideCentroidMs);

  // ── Direction (same logic as Algorithm 1, applied to weighted centroids) ───

  let direction: "in" | "out" | "unknown";
  if (centroidDeltaMs <= 1) {
    direction = "unknown";
  } else if (outsideCentroidMs < insideCentroidMs) {
    direction = "in";
  } else {
    direction = "out";
  }

  let timestamp: Date;
  if (direction === "in") {
    timestamp = new Date(outsideCentroidMs);
  } else if (direction === "out") {
    timestamp = new Date(insideCentroidMs);
  } else {
    timestamp = new Date((outsideCentroidMs + insideCentroidMs) / 2);
  }

  // ── Shared confidence factors (same formulae as Algorithm 1) ──────────────

  const centroidSeparationFactor =
    clusterDurationMs === 0
      ? CONFIDENCE_FACTOR_FLOOR
      : clamp(centroidDeltaMs / clusterDurationMs);

  const totalScans = outsideScans.length + insideScans.length;
  const clusterSizeFactor = clamp(Math.min(1.0, (totalScans - 2) / 8));

  const insideCount = insideScans.length;
  const outsideCount = outsideScans.length;
  const bilateralCoverageFactor = clamp(
    Math.min(insideCount, outsideCount) / Math.max(insideCount, outsideCount),
  );

  // ── RSSI trend analysis ────────────────────────────────────────────────────

  const outsideTrend = computeTrend(outsideScans, clusterStartMs);
  const insideTrend = computeTrend(insideScans, clusterStartMs);

  const trendFactor = rssiConsistencyFactor(
    outsideTrend,
    insideTrend,
    direction,
    outsideCount,
    insideCount,
  );

  const confidence =
    centroidSeparationFactor *
    clusterSizeFactor *
    bilateralCoverageFactor *
    trendFactor;

  // ── Metadata ───────────────────────────────────────────────────────────────

  return {
    algorithmId: "rssi_weighted_centroid",
    direction,
    confidence,
    centroidSeparationFactor,
    clusterSizeFactor,
    bilateralCoverageFactor,
    rssiTrendConsistencyFactor: trendFactor,
    timestamp,
    metadata: {
      outsideCentroidMs,
      insideCentroidMs,
      centroidDeltaMs,
      clusterDurationMs,
      outsideScanCount: outsideCount,
      insideScanCount: insideCount,
      rssiWeights: {
        outside: outsideScans.map((s) => rssiWeight(s.rssiDbm)),
        inside: insideScans.map((s) => rssiWeight(s.rssiDbm)),
      },
      rssiTrend: {
        outside: outsideTrend ?? { slope: 0, r2: 0 },
        inside: insideTrend ?? { slope: 0, r2: 0 },
      },
    },
  };
}
