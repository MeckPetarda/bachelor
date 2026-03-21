import type { PartitionedCluster, AlgorithmResult } from "./types";
import { CONFIDENCE_FACTOR_FLOOR } from "./types";

/**
 * Compute the arithmetic mean of an array of Date values as a Unix ms number.
 */
function centroid(dates: Date[]): number {
  const sum = dates.reduce((acc, d) => acc + d.getTime(), 0);
  return sum / dates.length;
}

/**
 * Algorithm 1 - Temporal Centroid.
 *
 * Pure function: no DB access, no side effects.
 *
 * Direction is determined by which lighthouse's time-centroid is earlier:
 *   outsideCentroid < insideCentroid  ->  "in"
 *   insideCentroid  < outsideCentroid ->  "out"
 *   |delta| <= 1 ms                   ->  "unknown"
 *
 * Confidence = centroidSeparationFactor * clusterSizeFactor * bilateralCoverageFactor
 * All factors are clamped to [CONFIDENCE_FACTOR_FLOOR, 1.0].
 */
export function analyzeTemporalCentroid(
  cluster: PartitionedCluster,
): AlgorithmResult {
  const { insideScans, outsideScans, clusterStartedAt, clusterEndedAt } =
    cluster;

  const outsideCentroidMs = centroid(outsideScans.map((s) => s.timestamp));
  const insideCentroidMs = centroid(insideScans.map((s) => s.timestamp));

  const centroidDeltaMs = Math.abs(outsideCentroidMs - insideCentroidMs);
  const clusterDurationMs =
    clusterEndedAt.getTime() - clusterStartedAt.getTime();

  // -- Direction --------------------------------------------------------------

  let direction: "in" | "out" | "unknown";
  if (centroidDeltaMs <= 1) {
    direction = "unknown";
  } else if (outsideCentroidMs < insideCentroidMs) {
    direction = "in";
  } else {
    direction = "out";
  }

  // -- Canonical event timestamp ----------------------------------------------
  //   "in"  -> entry side (outside) centroid
  //   "out" -> entry side (inside) centroid
  //   "unknown" -> midpoint

  let timestamp: Date;
  if (direction === "in") {
    timestamp = new Date(outsideCentroidMs);
  } else if (direction === "out") {
    timestamp = new Date(insideCentroidMs);
  } else {
    timestamp = new Date((outsideCentroidMs + insideCentroidMs) / 2);
  }

  // -- Confidence factors -----------------------------------------------------

  // 1. Centroid separation: how far apart are the two centroids relative to
  //    the total cluster duration. Zero duration -> floor.
  const centroidSeparationFactor =
    clusterDurationMs === 0
      ? CONFIDENCE_FACTOR_FLOOR
      : clamp(centroidDeltaMs / clusterDurationMs);

  // 2. Cluster size: more scans -> higher confidence. Saturates at 10 total.
  const totalScans = insideScans.length + outsideScans.length;
  const clusterSizeFactor = clamp(Math.min(1.0, (totalScans - 2) / 8));

  // 3. Bilateral coverage: penalise heavily unbalanced clusters.
  const insideCount = insideScans.length;
  const outsideCount = outsideScans.length;
  const bilateralCoverageFactor = clamp(
    Math.min(insideCount, outsideCount) / Math.max(insideCount, outsideCount),
  );

  const confidence =
    centroidSeparationFactor * clusterSizeFactor * bilateralCoverageFactor;

  return {
    algorithmId: "temporal_centroid",
    direction,
    confidence,
    centroidSeparationFactor,
    clusterSizeFactor,
    bilateralCoverageFactor,
    rssiTrendConsistencyFactor: null,
    timestamp,
    metadata: {
      outsideCentroidMs,
      insideCentroidMs,
      centroidDeltaMs,
      clusterDurationMs,
      outsideScanCount: outsideCount,
      insideScanCount: insideCount,
    },
  };
}

/** Clamp value to [CONFIDENCE_FACTOR_FLOOR, 1.0]. */
function clamp(value: number): number {
  return Math.max(CONFIDENCE_FACTOR_FLOOR, Math.min(1.0, value));
}
