import { type Component, For, Show, onMount } from "solid-js";
import { EventsTable } from "../components/EventsTable";
import {
  eventsState,
  fetchEvents,
  setFilter,
  nextPage,
  prevPage,
} from "../stores/events";
import {
  lighthousesState,
  fetchAll as fetchLighthouses,
} from "../stores/lighthouses";
import type { ScanSource } from "../types";
import styles from "./Events.module.css";

export const Events: Component = () => {
  onMount(() => {
    fetchLighthouses();
    fetchEvents();
  });

  const handleLighthouseFilter = (e: Event) => {
    const value = (e.target as HTMLSelectElement).value;
    setFilter("lighthouseId", value ? parseInt(value, 10) : undefined);
  };

  const handleEpcFilter = (e: Event) => {
    setFilter("epc", (e.target as HTMLInputElement).value);
  };

  const handleSourceFilter = (value: ScanSource | undefined) => {
    setFilter("source", value);
  };

  const currentPage = () =>
    Math.floor(eventsState.pagination.offset / eventsState.pagination.limit) +
    1;

  const totalPages = () =>
    Math.ceil(eventsState.pagination.total / eventsState.pagination.limit);

  const hasPrev = () => eventsState.pagination.offset > 0;
  const hasNext = () =>
    eventsState.pagination.offset + eventsState.pagination.limit <
    eventsState.pagination.total;

  return (
    <div class={styles.page}>
      <div class="page-header">
        <h1 class="page-title">Scan Events</h1>
      </div>

      <div class={styles.filters}>
        <div class={styles.filterGroup}>
          <label class="label">Lighthouse</label>
          <select
            class="select"
            value={eventsState.filters.lighthouseId ?? ""}
            onChange={handleLighthouseFilter}
          >
            <option value="">All lighthouses</option>
            <For each={lighthousesState.registered}>
              {(lighthouse) => (
                <option value={lighthouse.id}>{lighthouse.name}</option>
              )}
            </For>
          </select>
        </div>

        <div class={styles.filterGroup}>
          <label class="label">EPC</label>
          <input
            type="text"
            class="input"
            placeholder="Search by EPC..."
            value={eventsState.filters.epc}
            onInput={handleEpcFilter}
          />
        </div>

        <div class={styles.filterGroup}>
          <label class="label">Source</label>
          <div class={styles.toggleGroup}>
            <button
              class={`${styles.toggleBtn} ${
                eventsState.filters.source === undefined ? styles.active : ""
              }`}
              onClick={() => handleSourceFilter(undefined)}
            >
              All
            </button>
            <button
              class={`${styles.toggleBtn} ${
                eventsState.filters.source === "realtime" ? styles.active : ""
              }`}
              onClick={() => handleSourceFilter("realtime")}
            >
              Realtime
            </button>
            <button
              class={`${styles.toggleBtn} ${
                eventsState.filters.source === "offline_sync"
                  ? styles.active
                  : ""
              }`}
              onClick={() => handleSourceFilter("offline_sync")}
            >
              Offline Sync
            </button>
          </div>
        </div>
      </div>

      <EventsTable events={eventsState.events} loading={eventsState.loading} />

      <Show when={eventsState.pagination.total > 0}>
        <div class={styles.pagination}>
          <button
            class="btn btn-secondary btn-sm"
            disabled={!hasPrev()}
            onClick={prevPage}
          >
            Previous
          </button>
          <span class={styles.pageInfo}>
            Page {currentPage()} of {totalPages()} (
            {eventsState.pagination.total} total)
          </span>
          <button
            class="btn btn-secondary btn-sm"
            disabled={!hasNext()}
            onClick={nextPage}
          >
            Next
          </button>
        </div>
      </Show>
    </div>
  );
};
