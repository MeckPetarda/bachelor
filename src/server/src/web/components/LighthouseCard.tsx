import { type Component, Show, createSignal } from "solid-js";
import type { Lighthouse } from "../types";
import styles from "./LighthouseCard.module.css";

interface Props {
  lighthouse: Lighthouse;
}

export const LighthouseCard: Component<Props> = (props) => {
  const [expanded, setExpanded] = createSignal(false);

  const isConnected = () => props.lighthouse.runtime?.isConnected ?? false;
  const health = () => props.lighthouse.runtime?.health;

  const formatUptime = (seconds: number): string => {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }
    return `${minutes}m`;
  };

  const formatBytes = (bytes: number): string => {
    return `${Math.round(bytes / 1024)} KB`;
  };

  return (
    <div class={styles.card} onClick={() => setExpanded(!expanded())}>
      <div class={styles.header}>
        <div class={styles.status}>
          <span class={`status-dot ${isConnected() ? "online" : "offline"}`} />
          <span class={styles.name}>
            {props.lighthouse.label || props.lighthouse.name}
          </span>
        </div>
        <div class={styles.badges}>
          <Show when={props.lighthouse.group}>
            <span class="badge badge-info">
              {props.lighthouse.group!.label}
            </span>
          </Show>
          <span
            class={`badge ${placementBadgeClass(props.lighthouse.placement)}`}
          >
            {props.lighthouse.placement}
          </span>
        </div>
      </div>

      <div class={styles.deviceId}>{props.lighthouse.deviceId}</div>

      <Show when={expanded() && health()}>
        <div class={styles.health}>
          <div class={styles.healthRow}>
            <span class={styles.healthLabel}>Uptime</span>
            <span class={styles.healthValue}>
              {formatUptime(health()!.uptimeSec)}
            </span>
          </div>
          <div class={styles.healthRow}>
            <span class={styles.healthLabel}>Free Heap</span>
            <span class={styles.healthValue}>
              {formatBytes(health()!.freeHeapBytes)}
            </span>
          </div>
          <div class={styles.healthRow}>
            <span class={styles.healthLabel}>WiFi RSSI</span>
            <span class={styles.healthValue}>{health()!.wifiRssiDbm} dBm</span>
          </div>
          <div class={styles.healthRow}>
            <span class={styles.healthLabel}>RFID State</span>
            <span class={styles.healthValue}>
              {health()!.rfidState}
              <Show when={!health()!.rfidIsResponsive}>
                <span
                  class="badge badge-danger"
                  style={{ "margin-left": "0.5rem" }}
                >
                  Unresponsive
                </span>
              </Show>
              <Show when={health()!.rfidIsResponsive}>
                <span
                  class="badge badge-success"
                  style={{ "margin-left": "0.5rem" }}
                >
                  Responsive
                </span>
              </Show>
            </span>
          </div>
        </div>
      </Show>

      <Show when={expanded() && !health()}>
        <div class={styles.noHealth}>No health data available</div>
      </Show>
    </div>
  );
};

function placementBadgeClass(placement: string): string {
  switch (placement) {
    case "INSIDE":
      return "badge-success";
    case "OUTSIDE":
      return "badge-warning";
    default:
      return "badge-neutral";
  }
}
