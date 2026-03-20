import { type Component, For, Show, createSignal, onMount } from "solid-js";
import {
  processedEventsState,
  fetchEvents,
  fetchEventDetail,
  clearEventDetail,
} from "../stores/processedEvents";
import { groupsState, fetchAll as fetchGroups } from "../stores/groups";
import {
  pendingEventsAlgorithms,
  resetPendingEventsAlgorithms,
} from "../stores/websocket";
import { EventDetailModal } from "../components/EventDetailModal";
import * as api from "../api";
import type { ProcessedEvent, ProcessedEventsFilter } from "../types";
import styles from "./ProcessedEvents.module.css";

type AlgoTab = "temporal_centroid" | "rssi_weighted_centroid" | "both";

const LIMIT = 50;

// ── Formatting helpers ─────────────────────────────────────────────────────

function formatRelTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  if (diff < 60_000) return "Just now";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return new Date(iso).toLocaleString();
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function algoLabel(id: string): string {
  if (id === "temporal_centroid") return "Temporal";
  if (id === "rssi_weighted_centroid") return "RSSI";
  return "Manual";
}

// ── Component ─────────────────────────────────────────────────────────────

export const ProcessedEvents: Component = () => {
  // ── Filter state ─────────────────────────────────────────────────────────
  const [algoTab, setAlgoTab] = createSignal<AlgoTab>("temporal_centroid");
  const [search, setSearch] = createSignal("");
  const [direction, setDirection] = createSignal("");
  const [groupFilter, setGroupFilter] = createSignal<number | undefined>(undefined);
  const [dateFrom, setDateFrom] = createSignal("");
  const [dateTo, setDateTo] = createSignal("");
  const [page, setPage] = createSignal(0);

  // ── "Both" local state ────────────────────────────────────────────────────
  const [bothEvents, setBothEvents] = createSignal<ProcessedEvent[]>([]);
  const [bothTotal, setBothTotal] = createSignal(0);
  const [bothLoading, setBothLoading] = createSignal(false);

  // ── Modal state ───────────────────────────────────────────────────────────
  const [showModal, setShowModal] = createSignal(false);

  // ── Debounce timer ────────────────────────────────────────────────────────
  let debounceTimer: ReturnType<typeof setTimeout> | undefined;

  // ── Derived: common filters shared between single and both modes ──────────
  const commonFilters = (): Partial<ProcessedEventsFilter> => ({
    tagEpc: search() || undefined,
    direction: (direction() || undefined) as ProcessedEventsFilter["direction"],
    groupId: groupFilter(),
    from: dateFrom() || undefined,
    to: dateTo() || undefined,
    limit: LIMIT,
  });

  // ── Fetch for single-algorithm mode (uses the store) ──────────────────────
  const doFetchSingle = (offset = 0) => {
    fetchEvents({
      algorithmId: algoTab() as "temporal_centroid" | "rssi_weighted_centroid",
      ...commonFilters(),
      offset,
    });
  };

  // ── Fetch for both-algorithm mode (bypasses store for data) ──────────────
  const doFetchBoth = async () => {
    setBothLoading(true);
    try {
      const filters = { ...commonFilters(), offset: 0 };
      const [r1, r2] = await Promise.all([
        api.getProcessedEvents({ ...filters, algorithmId: "temporal_centroid" }),
        api.getProcessedEvents({ ...filters, algorithmId: "rssi_weighted_centroid" }),
      ]);
      const merged = [...r1.data, ...r2.data].sort(
        (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime(),
      );
      setBothEvents(merged);
      setBothTotal(r1.total + r2.total);
    } finally {
      setBothLoading(false);
    }
  };

  const doFetch = () => {
    if (algoTab() === "both") doFetchBoth();
    else doFetchSingle(0);
  };

  // ── Display values (unified single/both) ──────────────────────────────────
  const displayEvents = () =>
    algoTab() === "both" ? bothEvents() : processedEventsState.events;
  const displayTotal = () =>
    algoTab() === "both" ? bothTotal() : processedEventsState.total;
  const displayLoading = () =>
    algoTab() === "both" ? bothLoading() : processedEventsState.loading;

  // ── WebSocket new-events banner ───────────────────────────────────────────
  const newEventCount = () => {
    const algo = algoTab();
    const pending = pendingEventsAlgorithms();
    if (algo === "both") return pending.length;
    return pending.filter((a) => a === algo).length;
  };

  const handleRefresh = () => {
    resetPendingEventsAlgorithms();
    setPage(0);
    doFetch();
  };

  // ── Handlers ──────────────────────────────────────────────────────────────
  const handleAlgoTab = (tab: AlgoTab) => {
    setAlgoTab(tab);
    setPage(0);
    if (tab === "both") doFetchBoth();
    else fetchEvents({ algorithmId: tab, ...commonFilters(), offset: 0 });
  };

  const handleSearch = (e: Event) => {
    const val = (e.target as unknown as { value: string }).value;
    setSearch(val);
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      setPage(0);
      doFetch();
    }, 300);
  };

  const handleDirectionChange = (e: Event) => {
    setDirection((e.target as unknown as { value: string }).value);
    setPage(0);
    doFetch();
  };

  const handleGroupChange = (e: Event) => {
    const val = (e.target as unknown as { value: string }).value;
    setGroupFilter(val ? parseInt(val, 10) : undefined);
    setPage(0);
    doFetch();
  };

  const handleDateFrom = (e: Event) => {
    setDateFrom((e.target as unknown as { value: string }).value);
    setPage(0);
    doFetch();
  };

  const handleDateTo = (e: Event) => {
    setDateTo((e.target as unknown as { value: string }).value);
    setPage(0);
    doFetch();
  };

  const handlePrev = () => {
    const newPage = Math.max(0, page() - 1);
    setPage(newPage);
    doFetchSingle(newPage * LIMIT);
  };

  const handleNext = () => {
    const newPage = page() + 1;
    setPage(newPage);
    doFetchSingle(newPage * LIMIT);
  };

  const handleRowClick = (event: ProcessedEvent) => {
    fetchEventDetail(event.id);
    setShowModal(true);
  };

  const handleModalClose = () => {
    setShowModal(false);
    clearEventDetail();
  };

  const currentPage = () => page() + 1;
  const totalPages = () => Math.max(1, Math.ceil(displayTotal() / LIMIT));
  const hasPrev = () => page() > 0;
  const hasNext = () => (page() + 1) * LIMIT < displayTotal();

  const confClass = (c: number) => {
    if (c >= 0.7) return styles.confHigh;
    if (c >= 0.4) return styles.confMed;
    return styles.confLow;
  };

  const dirLabel = (d: string) => {
    if (d === "in") return "→ In";
    if (d === "out") return "← Out";
    return "? Unknown";
  };

  const dirClass = (d: string) => {
    if (d === "in") return styles.dirIn;
    if (d === "out") return styles.dirOut;
    return styles.dirUnknown;
  };

  onMount(() => {
    fetchGroups();
    fetchEvents({ algorithmId: "temporal_centroid", limit: LIMIT, offset: 0 });
  });

  return (
    <div class={styles.page}>
      <div class="page-header">
        <h1 class="page-title">Processed Events</h1>
      </div>

      {/* ── Filters ── */}
      <div class={styles.filters}>
        <div class={styles.filterGroup}>
          <label class="label">Algorithm</label>
          <div class={styles.toggleGroup}>
            <button
              class={`${styles.toggleBtn} ${algoTab() === "temporal_centroid" ? styles.active : ""}`}
              onClick={() => handleAlgoTab("temporal_centroid")}
            >
              Temporal
            </button>
            <button
              class={`${styles.toggleBtn} ${algoTab() === "rssi_weighted_centroid" ? styles.active : ""}`}
              onClick={() => handleAlgoTab("rssi_weighted_centroid")}
            >
              RSSI
            </button>
            <button
              class={`${styles.toggleBtn} ${algoTab() === "both" ? styles.active : ""}`}
              onClick={() => handleAlgoTab("both")}
            >
              Both
            </button>
          </div>
        </div>

        <div class={styles.filterGroup}>
          <label class="label">Search by EPC / Tag</label>
          <input
            type="text"
            class="input"
            placeholder="Full EPC..."
            value={search()}
            onInput={handleSearch}
          />
        </div>

        <div class={styles.filterGroup}>
          <label class="label">Direction</label>
          <select class="select" value={direction()} onChange={handleDirectionChange}>
            <option value="">All</option>
            <option value="in">In</option>
            <option value="out">Out</option>
            <option value="unknown">Unknown</option>
          </select>
        </div>

        <div class={styles.filterGroup}>
          <label class="label">Group</label>
          <select class="select" onChange={handleGroupChange}>
            <option value="">All groups</option>
            <For each={groupsState.groups}>
              {(g) => <option value={g.id}>{g.label}</option>}
            </For>
          </select>
        </div>

        <div class={styles.filterGroup}>
          <label class="label">From</label>
          <input
            type="datetime-local"
            class="input"
            value={dateFrom()}
            onInput={handleDateFrom}
          />
        </div>

        <div class={styles.filterGroup}>
          <label class="label">To</label>
          <input
            type="datetime-local"
            class="input"
            value={dateTo()}
            onInput={handleDateTo}
          />
        </div>
      </div>

      {/* ── New events banner ── */}
      <Show when={newEventCount() > 0}>
        <div class={styles.banner}>
          <span>
            {newEventCount()} new event{newEventCount() === 1 ? "" : "s"} detected
          </span>
          <button class={styles.bannerBtn} onClick={handleRefresh}>
            Click to refresh
          </button>
        </div>
      </Show>

      {/* ── Table ── */}
      <div class={styles.tableWrap}>
        <Show when={displayLoading()}>
          <div class={styles.loadingState}>Loading events…</div>
        </Show>

        <Show when={!displayLoading() && displayEvents().length === 0}>
          <div class={styles.emptyState}>No events found.</div>
        </Show>

        <Show when={!displayLoading() && displayEvents().length > 0}>
          <table class={styles.table}>
            <thead>
              <tr>
                <th>Direction</th>
                <th>Tag / User</th>
                <th>Group</th>
                <th>Confidence</th>
                <th>Algorithm</th>
                <th>Inside</th>
                <th>Outside</th>
                <th>Time</th>
                <th>Duration</th>
              </tr>
            </thead>
            <tbody>
              <For each={displayEvents()}>
                {(event) => (
                  <tr class={styles.row} onClick={() => handleRowClick(event)}>
                    <td class={dirClass(event.direction)}>{dirLabel(event.direction)}</td>
                    <td title={event.tagEpc}>
                      <Show when={event.userName} fallback={
                        <span class={styles.epcMono}>…{event.tagEpc.slice(-5)}</span>
                      }>
                        {event.userName}
                      </Show>
                    </td>
                    <td>{event.groupLabel}</td>
                    <td class={confClass(event.confidence)}>
                      {Math.round(event.confidence * 100)}%
                    </td>
                    <td>{algoLabel(event.algorithmId)}</td>
                    <td>{event.insideScanCount}</td>
                    <td>{event.outsideScanCount}</td>
                    <td>{formatRelTime(event.timestamp)}</td>
                    <td>
                      {formatDuration(
                        new Date(event.clusterEndedAt).getTime() -
                          new Date(event.clusterStartedAt).getTime(),
                      )}
                    </td>
                  </tr>
                )}
              </For>
            </tbody>
          </table>
        </Show>
      </div>

      {/* ── Pagination ── */}
      <Show when={algoTab() === "both"}>
        <p class={styles.bothNote}>
          Both mode shows the most recent {LIMIT} events per algorithm (
          {displayTotal()} total across both algorithms).
        </p>
      </Show>

      <Show when={algoTab() !== "both" && displayTotal() > LIMIT}>
        <div class={styles.pagination}>
          <button
            class="btn btn-secondary btn-sm"
            disabled={!hasPrev()}
            onClick={handlePrev}
          >
            Previous
          </button>
          <span class={styles.pageInfo}>
            Page {currentPage()} of {totalPages()} ({displayTotal()} total)
          </span>
          <button
            class="btn btn-secondary btn-sm"
            disabled={!hasNext()}
            onClick={handleNext}
          >
            Next
          </button>
        </div>
      </Show>

      {/* ── Detail modal ── */}
      <Show when={showModal()}>
        <EventDetailModal onClose={handleModalClose} />
      </Show>
    </div>
  );
};
