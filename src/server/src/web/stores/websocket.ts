import { createSignal } from "solid-js";
import {
  handleDeviceOnline,
  handleDeviceOffline,
  handleDeviceHealth,
  handleDevicePending,
} from "./lighthouses";
import { prependEvent } from "./events";
import type {
  WsMessage,
  WsScanPayload,
  WsDeviceOnlinePayload,
  WsDeviceOfflinePayload,
  WsDeviceHealthPayload,
  WsDevicePendingPayload,
  WsEventNewPayload,
  Scan,
} from "../types";

// Tracks algorithm IDs of processed events that arrived since last refresh
const [pendingEventsAlgorithms, setPendingEventsAlgorithms] = createSignal<
  string[]
>([]);

export function resetPendingEventsAlgorithms() {
  setPendingEventsAlgorithms([]);
}

export { pendingEventsAlgorithms };

const [connected, setConnected] = createSignal(false);

let ws: WebSocket | null = null;
let reconnectTimeout: number | null = null;

function getWsUrl(): string {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/ws`;
}

export function connect() {
  if (ws) {
    return;
  }

  ws = new WebSocket(getWsUrl());

  ws.onopen = () => {
    setConnected(true);
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout);
      reconnectTimeout = null;
    }
  };

  ws.onclose = () => {
    setConnected(false);
    ws = null;
    // Attempt to reconnect after 3 seconds
    reconnectTimeout = window.setTimeout(connect, 3000);
  };

  ws.onerror = () => {
    ws?.close();
  };

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data) as WsMessage;
      handleMessage(msg);
    } catch {
      console.error("Failed to parse WebSocket message");
    }
  };
}

export function disconnect() {
  if (reconnectTimeout) {
    clearTimeout(reconnectTimeout);
    reconnectTimeout = null;
  }
  if (ws) {
    ws.close();
    ws = null;
  }
}

function handleMessage(msg: WsMessage) {
  switch (msg.type) {
    case "scan": {
      const payload = msg.payload as WsScanPayload;
      const scan: Scan = {
        id: payload.id,
        lighthouseId: payload.lighthouseId,
        lighthouseName: payload.lighthouseName,
        epc: payload.epc,
        rssiDbm: payload.rssiDbm,
        timestamp: payload.timestamp,
        source: payload.source,
        receivedAt: msg.timestamp,
      };
      prependEvent(scan);
      break;
    }
    case "device:online": {
      const payload = msg.payload as WsDeviceOnlinePayload;
      handleDeviceOnline(payload.deviceId, payload.lighthouseId);
      break;
    }
    case "device:offline": {
      const payload = msg.payload as WsDeviceOfflinePayload;
      handleDeviceOffline(payload.deviceId, payload.lighthouseId);
      break;
    }
    case "device:health": {
      const payload = msg.payload as WsDeviceHealthPayload;
      handleDeviceHealth(
        payload.deviceId,
        payload.lighthouseId,
        payload.health,
      );
      break;
    }
    case "device:pending": {
      const payload = msg.payload as WsDevicePendingPayload;
      handleDevicePending(payload.deviceId);
      break;
    }
    case "event:new": {
      const payload = msg.payload as WsEventNewPayload;
      setPendingEventsAlgorithms((prev) => [...prev, payload.algorithmId]);
      break;
    }
  }
}

export { connected };
