type SyncPhase = "syncing" | "completed";
interface SyncEntry {
  phase: SyncPhase;
  ts: number;
}

const activeSyncs = new Map<number, SyncEntry>();

// A sync that started more than this long ago is considered stale (lighthouse
// crashed or disconnected mid-sync).
const SYNC_STALE_MS = 120_000;

// After sync/complete, hold the sweeper's orphan check for this long so a
// partner lighthouse has time to connect and start its own replay.
const SYNC_COMPLETE_HOLD_MS = 5 * 60_000;

export function markSyncStart(lighthouseId: number): void {
  activeSyncs.set(lighthouseId, { phase: "syncing", ts: Date.now() });
}

export function markSyncComplete(lighthouseId: number): void {
  activeSyncs.set(lighthouseId, { phase: "completed", ts: Date.now() });
}

export function hasActiveSyncInGroup(lighthouseIds: number[]): boolean {
  const now = Date.now();
  return lighthouseIds.some((id) => {
    const entry = activeSyncs.get(id);
    if (!entry) return false;
    if (entry.phase === "syncing") return now - entry.ts < SYNC_STALE_MS;
    return now - entry.ts < SYNC_COMPLETE_HOLD_MS;
  });
}
