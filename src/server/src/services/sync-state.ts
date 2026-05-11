// lighthouseId → epoch ms when sync/start was received
const activeSyncs = new Map<number, number>();

// A sync that started more than this long ago is considered stale (lighthouse
// crashed or disconnected mid-sync). Prevents permanent blocking of cluster
// processing when one lighthouse never sends sync/complete.
const SYNC_STALE_MS = 120_000;

export function markSyncStart(lighthouseId: number): void {
  activeSyncs.set(lighthouseId, Date.now());
}

export function markSyncComplete(lighthouseId: number): void {
  activeSyncs.delete(lighthouseId);
}

export function hasActiveSyncInGroup(lighthouseIds: number[]): boolean {
  const now = Date.now();
  return lighthouseIds.some((id) => {
    const started = activeSyncs.get(id);
    return started !== undefined && now - started < SYNC_STALE_MS;
  });
}
