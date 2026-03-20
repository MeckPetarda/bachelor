import { createStore } from "solid-js/store";
import * as api from "../api";
import type { ProcessedEvent, ProcessedEventDetail, ProcessedEventsFilter } from "../types";
import { showToast } from "./toast";

interface ProcessedEventsState {
  events: ProcessedEvent[];
  total: number;
  loading: boolean;
  error: string | null;
  filters: ProcessedEventsFilter;
  // Detail modal
  selectedEventDetail: ProcessedEventDetail | null;
  detailLoading: boolean;
}

const [state, setState] = createStore<ProcessedEventsState>({
  events: [],
  total: 0,
  loading: false,
  error: null,
  filters: {
    algorithmId: "temporal_centroid",
    limit: 50,
    offset: 0,
  },
  selectedEventDetail: null,
  detailLoading: false,
});

export async function fetchEvents(filters?: Partial<ProcessedEventsFilter>) {
  if (filters) {
    setState("filters", (prev) => ({ ...prev, ...filters }));
  }
  setState({ loading: true, error: null });
  try {
    const res = await api.getProcessedEvents(state.filters);
    setState({ events: res.data, total: res.total, loading: false });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to fetch events";
    setState({ error: message, loading: false });
    showToast(message, "error");
  }
}

export async function fetchEventDetail(id: string) {
  setState({ detailLoading: true, selectedEventDetail: null });
  try {
    const detail = await api.getProcessedEventDetail(id);
    setState({ selectedEventDetail: detail, detailLoading: false });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to fetch event detail";
    setState({ detailLoading: false });
    showToast(message, "error");
  }
}

export function clearEventDetail() {
  setState({ selectedEventDetail: null });
}

export function updateFilters(filters: Partial<ProcessedEventsFilter>) {
  setState("filters", (prev) => ({ ...prev, ...filters, offset: 0 }));
  fetchEvents();
}

export { state as processedEventsState };
