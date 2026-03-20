export interface ScanData {
  id: bigint;
  lighthouseId: number;
  epc: string;
  rssiDbm: number | null;
  timestamp: Date;
  timeBasis: "synced" | "estimated" | "relative";
}

export interface PartitionedCluster {
  epc: string;
  groupId: number;
  insideScans: ScanData[];
  outsideScans: ScanData[];
  allScans: ScanData[];
  clusterStartedAt: Date;
  clusterEndedAt: Date;
}

export type Direction = "in" | "out" | "unknown";

export interface AlgorithmResult {
  algorithmId: "temporal_centroid" | "rssi_weighted_centroid";
  direction: Direction;
  confidence: number;
  centroidSeparationFactor: number;
  clusterSizeFactor: number;
  bilateralCoverageFactor: number;
  rssiTrendConsistencyFactor: number | null;
  timestamp: Date;           // canonical event timestamp (entry-side centroid)
  metadata: Record<string, unknown>;
}

/**
 * Minimum value for any confidence factor.
 * Prevents any single factor from zeroing out the product.
 * TUNABLE — adjust after collecting real traversal data.
 */
export const CONFIDENCE_FACTOR_FLOOR = 0.1;
