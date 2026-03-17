import { type Component, For, Show, createSignal, onMount } from "solid-js";
import type { Scan } from "../types";
import styles from "./EventsTable.module.css";

interface Props {
  events: Scan[];
  loading: boolean;
}

export const EventsTable: Component<Props> = (props) => {
  const [highlightedId, setHighlightedId] = createSignal<string | null>(null);

  // Track new events for highlight animation
  let lastFirstId: string | null = null;

  onMount(() => {
    if (props.events.length > 0) {
      lastFirstId = props.events[0].id;
    }
  });

  // Check if the first event is new (for highlight)
  const isNewEvent = (id: string) => {
    return highlightedId() === id;
  };

  // Update highlight when events change
  const checkNewEvent = () => {
    if (props.events.length > 0 && props.events[0].id !== lastFirstId) {
      const newId = props.events[0].id;
      setHighlightedId(newId);
      lastFirstId = newId;

      // Remove highlight after animation
      setTimeout(() => {
        setHighlightedId(null);
      }, 2000);
    }
  };

  // Call this reactively
  (() => {
    checkNewEvent();
  })();

  const formatTime = (isoString: string): string => {
    const date = new Date(isoString);
    return date.toLocaleTimeString();
  };

  const formatDate = (isoString: string): string => {
    const date = new Date(isoString);
    return date.toLocaleDateString() + " " + date.toLocaleTimeString();
  };

  return (
    <div class={styles.container}>
      <Show when={props.loading}>
        <div class={styles.loading}>Loading...</div>
      </Show>

      <Show when={!props.loading && props.events.length === 0}>
        <div class={styles.empty}>No scan events found</div>
      </Show>

      <Show when={!props.loading && props.events.length > 0}>
        <table class={styles.table}>
          <thead>
            <tr>
              <th>Time</th>
              <th>Lighthouse</th>
              <th>EPC</th>
              <th>RSSI</th>
              <th>Source</th>
            </tr>
          </thead>
          <tbody>
            <For each={props.events}>
              {(event) => (
                <tr
                  class={isNewEvent(event.id) ? styles.highlight : ""}
                  title={formatDate(event.timestamp)}
                >
                  <td class={styles.time}>{formatTime(event.timestamp)}</td>
                  <td>{event.lighthouseName}</td>
                  <td class={styles.epc}>{event.epc}</td>
                  <td class={styles.rssi}>{event.rssiDbm} dBm</td>
                  <td>
                    <Show when={event.source === "offline_sync"}>
                      <span class="badge badge-warning">Offline</span>
                    </Show>
                    <Show when={event.source === "realtime"}>
                      <span class="badge badge-success">Live</span>
                    </Show>
                  </td>
                </tr>
              )}
            </For>
          </tbody>
        </table>
      </Show>
    </div>
  );
};
