import { createStore } from "solid-js/store";
import * as api from "../api";
import { showToast } from "./toast";
import type { Scan, ScanSource, ScansFilter } from "../types";

interface EventsState {
  events: Scan[];
  filters: {
    lighthouseId: number | undefined;
    epc: string;
    source: ScanSource | undefined;
  };
  pagination: {
    limit: number;
    offset: number;
    total: number;
  };
  loading: boolean;
  error: string | null;
}

const [state, setState] = createStore<EventsState>({
  events: [],
  filters: {
    lighthouseId: undefined,
    epc: "",
    source: undefined,
  },
  pagination: {
    limit: 50,
    offset: 0,
    total: 0,
  },
  loading: false,
  error: null,
});

export async function fetchEvents() {
  setState({ loading: true, error: null });
  try {
    const filters: ScansFilter = {
      limit: state.pagination.limit,
      offset: state.pagination.offset,
    };

    if (state.filters.lighthouseId !== undefined) {
      filters.lighthouseId = state.filters.lighthouseId;
    }
    if (state.filters.epc) {
      filters.epc = state.filters.epc;
    }
    if (state.filters.source) {
      filters.source = state.filters.source;
    }

    const res = await api.getScans(filters);
    setState({
      events: res.data,
      pagination: {
        limit: res.limit,
        offset: res.offset,
        total: res.total,
      },
      loading: false,
    });
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to fetch events";
    setState({ error: message, loading: false });
    showToast(message, "error");
  }
}

export function setFilter<K extends keyof EventsState["filters"]>(
  key: K,
  value: EventsState["filters"][K],
) {
  setState("filters", key, value);
  setState("pagination", "offset", 0);
  fetchEvents();
}

export function nextPage() {
  const newOffset = state.pagination.offset + state.pagination.limit;
  if (newOffset < state.pagination.total) {
    setState("pagination", "offset", newOffset);
    fetchEvents();
  }
}

export function prevPage() {
  const newOffset = Math.max(
    0,
    state.pagination.offset - state.pagination.limit,
  );
  if (newOffset !== state.pagination.offset) {
    setState("pagination", "offset", newOffset);
    fetchEvents();
  }
}

export function prependEvent(event: Scan) {
  // Only prepend if it matches current filters
  const { filters } = state;

  if (
    filters.lighthouseId !== undefined &&
    event.lighthouseId !== filters.lighthouseId
  ) {
    return;
  }
  if (
    filters.epc &&
    !event.epc.toLowerCase().includes(filters.epc.toLowerCase())
  ) {
    return;
  }
  if (filters.source && event.source !== filters.source) {
    return;
  }

  setState("events", (events) => [
    event,
    ...events.slice(0, state.pagination.limit - 1),
  ]);
  setState("pagination", "total", (t) => t + 1);
}

export { state as eventsState };
