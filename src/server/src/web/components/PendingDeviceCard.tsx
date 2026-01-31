import { type Component } from 'solid-js';
import type { PendingDevice } from '../types';
import styles from './PendingDeviceCard.module.css';

interface Props {
  device: PendingDevice;
  onClaim: () => void;
}

export const PendingDeviceCard: Component<Props> = (props) => {
  return (
    <div class={styles.card}>
      <div class={styles.header}>
        <div class={styles.status}>
          <span class={`status-dot ${props.device.isConnected ? 'online' : 'offline'}`} />
          <span class={styles.deviceId}>{props.device.deviceId}</span>
        </div>
      </div>

      <div class={styles.info}>
        <span class={styles.label}>First seen:</span>
        <span>{formatTime(props.device.firstSeenAt)}</span>
      </div>

      <button class="btn btn-primary btn-sm" onClick={props.onClaim}>
        Claim Device
      </button>
    </div>
  );
};

function formatTime(isoString: string): string {
  const date = new Date(isoString);
  return date.toLocaleString();
}
