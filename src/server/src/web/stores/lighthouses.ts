import { createStore } from "solid-js/store";
import * as api from "../api";
import { showToast } from "./toast";
import type {
  Lighthouse,
  PendingDevice,
  ClaimDeviceRequest,
  UpdateLighthouseRequest,
  Health,
} from "../types";

interface LighthousesState {
  registered: Lighthouse[];
  pending: PendingDevice[];
  loading: boolean;
  error: string | null;
}

const [state, setState] = createStore<LighthousesState>({
  registered: [],
  pending: [],
  loading: false,
  error: null,
});

export async function fetchAll() {
  setState({ loading: true, error: null });
  try {
    const [lighthousesRes, pendingRes] = await Promise.all([
      api.getLighthouses(),
      api.getPendingDevices(),
    ]);
    setState({
      registered: lighthousesRes.data,
      pending: pendingRes.data,
      loading: false,
    });
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to fetch devices";
    setState({ error: message, loading: false });
    showToast(message, "error");
  }
}

export async function claimDevice(deviceId: string, data: ClaimDeviceRequest) {
  try {
    const lighthouse = await api.claimDevice(deviceId, data);
    setState((s) => ({
      registered: [...s.registered, lighthouse],
      pending: s.pending.filter((d) => d.deviceId !== deviceId),
    }));
    showToast(`Device "${data.name}" claimed successfully`, "success");
    return lighthouse;
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to claim device";
    showToast(message, "error");
    throw err;
  }
}

export async function updateLighthouse(
  id: number,
  data: UpdateLighthouseRequest,
) {
  try {
    const updated = await api.updateLighthouse(id, data);
    setState("registered", (lighthouses) =>
      lighthouses.map((l) => (l.id === id ? { ...l, ...updated } : l)),
    );
    showToast("Lighthouse updated", "success");
    return updated;
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to update lighthouse";
    showToast(message, "error");
    throw err;
  }
}

// WebSocket handlers
export function handleDeviceOnline(
  deviceId: string,
  lighthouseId: number | null,
) {
  if (lighthouseId !== null) {
    setState(
      "registered",
      (l) => l.id === lighthouseId,
      "runtime",
      (r) => ({
        ...r,
        isConnected: true,
      }),
    );
  } else {
    // Could be a pending device coming online
    setState("pending", (d) => d.deviceId === deviceId, "isConnected", true);
  }
}

export function handleDeviceOffline(
  deviceId: string,
  lighthouseId: number | null,
) {
  if (lighthouseId !== null) {
    setState("registered", (l) => l.id === lighthouseId, "runtime", {
      isConnected: false,
      lastHealthAt: null,
      health: null,
    });
    const lighthouse = state.registered.find((l) => l.id === lighthouseId);
    if (lighthouse) {
      showToast(`Device went offline: ${lighthouse.name}`, "warning");
    }
  } else {
    setState("pending", (d) => d.deviceId === deviceId, "isConnected", false);
  }
}

export function handleDeviceHealth(
  deviceId: string,
  lighthouseId: number | null,
  health: Health,
) {
  const now = new Date().toISOString();
  if (lighthouseId !== null) {
    setState("registered", (l) => l.id === lighthouseId, "runtime", {
      isConnected: true,
      lastHealthAt: now,
      health,
    });
  } else {
    setState("pending", (d) => d.deviceId === deviceId, {
      isConnected: true,
      lastHealthAt: now,
      health,
    });
  }
}

export function handleDevicePending(deviceId: string) {
  // Refresh pending list to get the new device
  api.getPendingDevices().then((res) => {
    setState("pending", res.data);
  });
  showToast(`New device detected: ${deviceId}`, "info");
}

export { state as lighthousesState };
