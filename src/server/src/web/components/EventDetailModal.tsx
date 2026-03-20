import { type Accessor, type Component, For, Show, createSignal, onMount, onCleanup } from "solid-js";
import { processedEventsState, fetchEventDetail } from "../stores/processedEvents";
import type { CompanionEvent, ProcessedEventDetail, ProcessedEventScan } from "../types";
import styles from "./EventDetailModal.module.css";

// ── SVG constants ──────────────────────────────────────────────────────────
const W = 700, H = 280;
const PL = 52, PR = 20, PT = 24, PB = 44;
const CW = W - PL - PR;  // 628
const CH = H - PT - PB;  // 212

const COLOR_OUTSIDE = "#3b82f6";
const COLOR_INSIDE  = "#f97316";

// ── Formatting helpers ─────────────────────────────────────────────────────

function fmtTime(iso: string): string {
  return new Date(iso).toLocaleString();
}

function fmtDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function algoFull(id: string): string {
  if (id === "temporal_centroid") return "Temporal Centroid";
  if (id === "rssi_weighted_centroid") return "RSSI-Weighted Centroid";
  return "Manual";
}

function mean(vals: number[]): number {
  if (vals.length === 0) return 0;
  return vals.reduce((s, v) => s + v, 0) / vals.length;
}

// ── Histogram builder ──────────────────────────────────────────────────────

type HistBin = { inside: number; outside: number; startMs: number };

function buildHistogram(
  inside: ProcessedEventScan[],
  outside: ProcessedEventScan[],
  startMs: number,
  durationMs: number,
): { bins: HistBin[]; binWidthMs: number; maxCount: number } {
  const dur = Math.max(durationMs, 1);
  const binWidthMs = Math.max(50, dur / 15);
  const numBins = Math.ceil(dur / binWidthMs);

  const bins: HistBin[] = Array.from({ length: numBins }, (_, i) => ({
    inside: 0,
    outside: 0,
    startMs: i * binWidthMs,
  }));

  const addScan = (scan: ProcessedEventScan, side: "inside" | "outside") => {
    const relMs = new Date(scan.timestamp).getTime() - startMs;
    const idx = Math.max(0, Math.min(numBins - 1, Math.floor(relMs / binWidthMs)));
    bins[idx]![side]++;
  };

  inside.forEach((s) => addScan(s, "inside"));
  outside.forEach((s) => addScan(s, "outside"));

  const maxCount = Math.max(1, ...bins.map((b) => b.inside + b.outside));
  return { bins, binWidthMs, maxCount };
}

// ── SVG helpers ────────────────────────────────────────────────────────────

function xScale(relMs: number, durationMs: number): number {
  return PL + (relMs / Math.max(durationMs, 1)) * CW;
}

function yScaleCount(count: number, maxCount: number): number {
  return PT + CH - (count / maxCount) * CH;
}

function yScaleRssi(rssi: number, rssiMin: number, rssiMax: number): number {
  return PT + ((rssiMax - rssi) / Math.max(rssiMax - rssiMin, 1)) * CH;
}

// ── Histogram SVG ──────────────────────────────────────────────────────────

const HistogramChart: Component<{
  inside: ProcessedEventScan[];
  outside: ProcessedEventScan[];
  startMs: number;
  durationMs: number;
  outsideCentroidMs: number;
  insideCentroidMs: number;
  label: string;
}> = (props) => {
  const hist = () =>
    buildHistogram(props.inside, props.outside, props.startMs, props.durationMs);

  const barW = () =>
    Math.max(2, (hist().binWidthMs / Math.max(props.durationMs, 1)) * CW - 1);

  const xAxisTicks = () => [0, 0.25, 0.5, 0.75, 1.0];

  const outsideX = () =>
    xScale(props.outsideCentroidMs - props.startMs, props.durationMs);
  const insideX = () =>
    xScale(props.insideCentroidMs - props.startMs, props.durationMs);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} class={styles.chartSvg}>
      {/* Axes */}
      <line x1={PL} y1={PT} x2={PL} y2={PT + CH} stroke="#e2e8f0" stroke-width="1" />
      <line x1={PL} y1={PT + CH} x2={PL + CW} y2={PT + CH} stroke="#e2e8f0" stroke-width="1" />

      {/* Y-axis ticks */}
      {[0, 0.5, 1].map((frac) => {
        const count = Math.round(frac * hist().maxCount);
        const y = yScaleCount(count, hist().maxCount);
        return (
          <>
            <line x1={PL - 4} y1={y} x2={PL} y2={y} stroke="#94a3b8" stroke-width="1" />
            <text x={PL - 7} y={y + 4} text-anchor="end" font-size="9" fill="#94a3b8">
              {count}
            </text>
          </>
        );
      })}

      {/* X-axis ticks */}
      {xAxisTicks().map((frac) => {
        const x = PL + frac * CW;
        const ms = Math.round(frac * props.durationMs);
        return (
          <>
            <line x1={x} y1={PT + CH} x2={x} y2={PT + CH + 4} stroke="#94a3b8" stroke-width="1" />
            <text x={x} y={PT + CH + 16} text-anchor="middle" font-size="9" fill="#94a3b8">
              {ms}ms
            </text>
          </>
        );
      })}

      {/* Y-axis label */}
      <text
        x={12}
        y={PT + CH / 2}
        text-anchor="middle"
        font-size="9"
        fill="#94a3b8"
        transform={`rotate(-90, 12, ${PT + CH / 2})`}
      >
        Scans
      </text>

      {/* Stacked bars */}
      {hist().bins.map((bin) => {
        const bx = xScale(bin.startMs, props.durationMs);
        const bw = barW();
        const outH = (bin.outside / hist().maxCount) * CH;
        const inH = (bin.inside / hist().maxCount) * CH;
        return (
          <>
            <rect
              x={bx}
              y={PT + CH - outH}
              width={bw}
              height={outH}
              fill={COLOR_OUTSIDE}
              opacity="0.8"
            />
            <rect
              x={bx}
              y={PT + CH - outH - inH}
              width={bw}
              height={inH}
              fill={COLOR_INSIDE}
              opacity="0.8"
            />
          </>
        );
      })}

      {/* Outside centroid line */}
      <Show when={outsideX() >= PL && outsideX() <= PL + CW}>
        <line
          x1={outsideX()}
          y1={PT}
          x2={outsideX()}
          y2={PT + CH}
          stroke={COLOR_OUTSIDE}
          stroke-width="2"
          stroke-dasharray="5,3"
        />
        <text x={outsideX() + 3} y={PT + 13} font-size="9" fill={COLOR_OUTSIDE}>
          Outside
        </text>
      </Show>

      {/* Inside centroid line */}
      <Show when={insideX() >= PL && insideX() <= PL + CW}>
        <line
          x1={insideX()}
          y1={PT}
          x2={insideX()}
          y2={PT + CH}
          stroke={COLOR_INSIDE}
          stroke-width="2"
          stroke-dasharray="5,3"
        />
        <text x={insideX() + 3} y={PT + 24} font-size="9" fill={COLOR_INSIDE}>
          Inside
        </text>
      </Show>
    </svg>
  );
};

// ── RSSI Scatter SVG ───────────────────────────────────────────────────────

const RssiScatterChart: Component<{
  inside: ProcessedEventScan[];
  outside: ProcessedEventScan[];
  startMs: number;
  durationMs: number;
  outsideSlope: number;
  insideSlope: number;
}> = (props) => {
  const allRssi = () =>
    [...props.inside, ...props.outside]
      .map((s) => s.rssiDbm)
      .filter((r): r is number => r !== null);

  const rssiMin = () => Math.min(...allRssi()) - 5;
  const rssiMax = () => Math.max(...allRssi()) + 5;

  const sx = (relMs: number) => xScale(relMs, props.durationMs);
  const sy = (rssi: number) => yScaleRssi(rssi, rssiMin(), rssiMax());

  // Trend line endpoints using (slope, mean point)
  const trendLine = (
    scans: ProcessedEventScan[],
    slope: number,
  ): [number, number, number, number] | null => {
    const valid = scans.filter((s) => s.rssiDbm !== null);
    if (valid.length < 2) return null;
    const mxVals = valid.map((s) => new Date(s.timestamp).getTime() - props.startMs);
    const myVals = valid.map((s) => s.rssiDbm as number);
    const mx = mean(mxVals);
    const my = mean(myVals);
    const y0 = my - slope * mx;
    const y1 = my + slope * (props.durationMs - mx);
    return [PL, sy(y0), PL + CW, sy(y1)];
  };

  const xAxisTicks = () => [0, 0.25, 0.5, 0.75, 1.0];
  const yAxisTicks = () => {
    const min = rssiMin(), max = rssiMax();
    const step = Math.ceil((max - min) / 4);
    const ticks: number[] = [];
    for (let v = Math.ceil(min); v <= max; v += step) ticks.push(v);
    return ticks;
  };

  return (
    <svg viewBox={`0 0 ${W} ${H}`} class={styles.chartSvg}>
      {/* Axes */}
      <line x1={PL} y1={PT} x2={PL} y2={PT + CH} stroke="#e2e8f0" stroke-width="1" />
      <line x1={PL} y1={PT + CH} x2={PL + CW} y2={PT + CH} stroke="#e2e8f0" stroke-width="1" />

      {/* Y-axis ticks (RSSI dBm) */}
      {yAxisTicks().map((val) => {
        const y = sy(val);
        return (
          <>
            <line x1={PL - 4} y1={y} x2={PL} y2={y} stroke="#94a3b8" stroke-width="1" />
            <text x={PL - 7} y={y + 4} text-anchor="end" font-size="9" fill="#94a3b8">
              {val}
            </text>
          </>
        );
      })}

      {/* X-axis ticks */}
      {xAxisTicks().map((frac) => {
        const x = PL + frac * CW;
        const ms = Math.round(frac * props.durationMs);
        return (
          <>
            <line x1={x} y1={PT + CH} x2={x} y2={PT + CH + 4} stroke="#94a3b8" stroke-width="1" />
            <text x={x} y={PT + CH + 16} text-anchor="middle" font-size="9" fill="#94a3b8">
              {ms}ms
            </text>
          </>
        );
      })}

      {/* Axis labels */}
      <text
        x={12}
        y={PT + CH / 2}
        text-anchor="middle"
        font-size="9"
        fill="#94a3b8"
        transform={`rotate(-90, 12, ${PT + CH / 2})`}
      >
        RSSI (dBm)
      </text>

      {/* Outside trend line */}
      {(() => {
        const pts = trendLine(props.outside, props.outsideSlope);
        if (!pts) return null;
        const [x1, y1, x2, y2] = pts;
        return (
          <line
            x1={x1} y1={Math.max(PT, Math.min(PT + CH, y1))}
            x2={x2} y2={Math.max(PT, Math.min(PT + CH, y2))}
            stroke={COLOR_OUTSIDE}
            stroke-width="1.5"
            stroke-dasharray="6,3"
            opacity="0.8"
          />
        );
      })()}

      {/* Inside trend line */}
      {(() => {
        const pts = trendLine(props.inside, props.insideSlope);
        if (!pts) return null;
        const [x1, y1, x2, y2] = pts;
        return (
          <line
            x1={x1} y1={Math.max(PT, Math.min(PT + CH, y1))}
            x2={x2} y2={Math.max(PT, Math.min(PT + CH, y2))}
            stroke={COLOR_INSIDE}
            stroke-width="1.5"
            stroke-dasharray="6,3"
            opacity="0.8"
          />
        );
      })()}

      {/* Outside scan dots */}
      <For each={props.outside.filter((s) => s.rssiDbm !== null)}>
        {(scan) => (
          <circle
            cx={sx(new Date(scan.timestamp).getTime() - props.startMs)}
            cy={sy(scan.rssiDbm!)}
            r="4"
            fill={COLOR_OUTSIDE}
            opacity="0.65"
          />
        )}
      </For>

      {/* Inside scan dots */}
      <For each={props.inside.filter((s) => s.rssiDbm !== null)}>
        {(scan) => (
          <circle
            cx={sx(new Date(scan.timestamp).getTime() - props.startMs)}
            cy={sy(scan.rssiDbm!)}
            r="4"
            fill={COLOR_INSIDE}
            opacity="0.65"
          />
        )}
      </For>
    </svg>
  );
};

// ── Main modal component ────────────────────────────────────────────────────

interface EventDetailModalProps {
  onClose: () => void;
}

export const EventDetailModal: Component<EventDetailModalProps> = (props) => {
  const [activeTab, setActiveTab] = createSignal<"overview" | "scans" | "timeline">(
    "overview",
  );

  const detail = () => processedEventsState.selectedEventDetail;
  const loading = () => processedEventsState.detailLoading;

  // Close on Escape
  const onKey = (e: { key: string }) => {
    if (e.key === "Escape") props.onClose();
  };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const doc = (globalThis as any).document as { addEventListener: Function; removeEventListener: Function } | undefined;
  onMount(() => doc?.addEventListener("keydown", onKey));
  onCleanup(() => doc?.removeEventListener("keydown", onKey));

  const handleCompanionClick = (companionId: string) => {
    setActiveTab("overview");
    fetchEventDetail(companionId);
  };

  // Relative timestamp within cluster (for raw scans tab)
  const relMs = (scanIso: string, startIso: string): string => {
    const diff = new Date(scanIso).getTime() - new Date(startIso).getTime();
    return `+${diff}ms`;
  };

  return (
    <div class={styles.overlay} onClick={props.onClose}>
      <div class={styles.modal} onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div class={styles.header}>
          <span class={styles.title}>
            <Show when={detail()} fallback="Event Detail">
              {(d: Accessor<ProcessedEventDetail>) =>
                `${d().event.algorithmId === "temporal_centroid" ? "Temporal" : d().event.algorithmId === "rssi_weighted_centroid" ? "RSSI" : "Manual"} — ${d().event.direction === "in" ? "→ Entry" : d().event.direction === "out" ? "← Exit" : "Unknown"}`
              }
            </Show>
          </span>
          <button class={styles.closeBtn} onClick={props.onClose}>
            ✕
          </button>
        </div>

        {/* Tabs */}
        <div class={styles.tabs}>
          {(["overview", "scans", "timeline"] as const).map((tab) => (
            <button
              class={`${styles.tab} ${activeTab() === tab ? styles.tabActive : ""}`}
              onClick={() => setActiveTab(tab)}
            >
              {tab === "overview" ? "Overview" : tab === "scans" ? "Raw Scans" : "Timeline"}
            </button>
          ))}
        </div>

        {/* Body */}
        <div class={styles.body}>
          <Show when={loading()}>
            <div class={styles.loadingState}>Loading event detail…</div>
          </Show>

          <Show when={detail()}>
            {(d: Accessor<ProcessedEventDetail>) => (
              <>
                {/* ── OVERVIEW TAB ── */}
                <Show when={activeTab() === "overview"}>
                  {/* Key-value grid */}
                  <div class={styles.grid}>
                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>Direction</span>
                      <span
                        class={
                          d().event.direction === "in"
                            ? styles.dirIn
                            : d().event.direction === "out"
                              ? styles.dirOut
                              : ""
                        }
                      >
                        {d().event.direction === "in"
                          ? "→ Entry"
                          : d().event.direction === "out"
                            ? "← Exit"
                            : "? Unknown"}
                      </span>
                    </div>

                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>Confidence</span>
                      <span class={styles.kvValue}>
                        {Math.round(d().event.confidence * 100)}%
                      </span>
                    </div>

                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>Tag EPC</span>
                      <span class={`${styles.kvValue} ${styles.mono}`}>
                        {d().event.tagEpc}
                      </span>
                    </div>

                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>User</span>
                      <span class={styles.kvValue}>
                        {d().event.userName
                          ? `${d().event.userName}${d().event.userSyncId ? ` (${d().event.userSyncId})` : ""}`
                          : "Unassigned"}
                      </span>
                    </div>

                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>Group</span>
                      <span class={styles.kvValue}>{d().event.groupLabel}</span>
                    </div>

                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>Algorithm</span>
                      <span class={styles.kvValue}>{algoFull(d().event.algorithmId)}</span>
                    </div>

                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>Timestamp</span>
                      <span class={styles.kvValue}>{fmtTime(d().event.timestamp)}</span>
                    </div>

                    <div class={styles.kvRow}>
                      <span class={styles.kvLabel}>Cluster span</span>
                      <span class={styles.kvValue}>
                        {fmtTime(d().event.clusterStartedAt)} →{" "}
                        {fmtTime(d().event.clusterEndedAt)} (
                        {fmtDuration(
                          new Date(d().event.clusterEndedAt).getTime() -
                            new Date(d().event.clusterStartedAt).getTime(),
                        )}
                        )
                      </span>
                    </div>
                  </div>

                  {/* Confidence factor bars */}
                  <p class={styles.sectionTitle}>Confidence Factors</p>
                  <div class={styles.factorBars}>
                    {(
                      [
                        ["Centroid separation", d().event.centroidSeparationFactor],
                        ["Cluster size", d().event.clusterSizeFactor],
                        ["Bilateral coverage", d().event.bilateralCoverageFactor],
                        ["RSSI trend", d().event.rssiTrendConsistencyFactor],
                      ] as [string, number | null][]
                    ).map(([label, value]) => (
                      <div class={styles.factorRow}>
                        <span class={styles.factorLabel}>{label}</span>
                        <Show
                          when={value !== null}
                          fallback={<span class={styles.naText}>N/A</span>}
                        >
                          <div class={styles.barTrack}>
                            <div
                              class={styles.barFill}
                              style={{ width: `${(value as number) * 100}%` }}
                            />
                          </div>
                        </Show>
                        <span class={styles.factorValue}>
                          {value !== null ? `${Math.round((value as number) * 100)}%` : "—"}
                        </span>
                      </div>
                    ))}
                  </div>

                  {/* Companion event */}
                  <Show when={d().companionEvent}>
                    {(comp: Accessor<CompanionEvent>) => (
                      <div class={styles.companion}>
                        <span>
                          Also analyzed by{" "}
                          <strong>{algoFull(comp().algorithmId)}</strong> →{" "}
                          confidence {Math.round(comp().confidence * 100)}%
                        </span>
                        <button
                          class={styles.companionBtn}
                          onClick={() => handleCompanionClick(comp().id)}
                        >
                          View companion →
                        </button>
                      </div>
                    )}
                  </Show>
                </Show>

                {/* ── RAW SCANS TAB ── */}
                <Show when={activeTab() === "scans"}>
                  {(["inside", "outside"] as const).map((side) => {
                    const lhScans = d().scans[side];
                    return (
                      <div class={styles.scanSection}>
                        <p class={styles.scanSectionTitle}>
                          {side === "inside" ? "Inside" : "Outside"} —{" "}
                          {lhScans.lighthouseName || "No lighthouse"} (
                          {lhScans.scans.length} scans)
                        </p>
                        <Show
                          when={lhScans.scans.length > 0}
                          fallback={
                            <p class={styles.scanEmpty}>No scans on this side.</p>
                          }
                        >
                          <table class={styles.scanTable}>
                            <thead>
                              <tr>
                                <th>Δ from start</th>
                                <th>RSSI (dBm)</th>
                                <th>Antenna</th>
                                <th>Frequency</th>
                                <th>Source</th>
                                <th>Basis</th>
                              </tr>
                            </thead>
                            <tbody>
                              <For each={lhScans.scans}>
                                {(scan) => (
                                  <tr>
                                    <td class={styles.mono}>
                                      {relMs(scan.timestamp, d().event.clusterStartedAt)}
                                    </td>
                                    <td>{scan.rssiDbm ?? "—"}</td>
                                    <td>{scan.antennaId ?? "—"}</td>
                                    <td>{scan.frequency ?? "—"}</td>
                                    <td>{scan.source}</td>
                                    <td>{scan.timeBasis}</td>
                                  </tr>
                                )}
                              </For>
                            </tbody>
                          </table>
                        </Show>
                      </div>
                    );
                  })}
                </Show>

                {/* ── TIMELINE TAB ── */}
                <Show when={activeTab() === "timeline"}>
                  <Show
                    when={d().event.algorithmId !== "manual"}
                    fallback={
                      <p class={styles.noData}>Manual event — no scan data to visualize.</p>
                    }
                  >
                    {(() => {
                      const startMs = new Date(d().event.clusterStartedAt).getTime();
                      const endMs = new Date(d().event.clusterEndedAt).getTime();
                      const durationMs = Math.max(endMs - startMs, 1);
                      const meta = d().event.metadata as Record<string, unknown>;
                      const outsideCentroidMs = (meta.outsideCentroidMs as number) ?? startMs;
                      const insideCentroidMs = (meta.insideCentroidMs as number) ?? endMs;

                      return (
                        <>
                          {/* Histogram chart */}
                          <div class={styles.chartSection}>
                            <p class={styles.chartTitle}>
                              {d().event.algorithmId === "rssi_weighted_centroid"
                                ? "RSSI-Weighted Scan Timing"
                                : "Scan Timing Histogram"}
                            </p>
                            <HistogramChart
                              inside={d().scans.inside.scans}
                              outside={d().scans.outside.scans}
                              startMs={startMs}
                              durationMs={durationMs}
                              outsideCentroidMs={outsideCentroidMs}
                              insideCentroidMs={insideCentroidMs}
                              label="histogram"
                            />
                            <div class={styles.legend}>
                              <div class={styles.legendItem}>
                                <div
                                  class={styles.legendDot}
                                  style={{ background: COLOR_OUTSIDE }}
                                />
                                <span>
                                  Outside — {d().scans.outside.lighthouseName || "Unknown"}
                                </span>
                              </div>
                              <div class={styles.legendItem}>
                                <div
                                  class={styles.legendDot}
                                  style={{ background: COLOR_INSIDE }}
                                />
                                <span>
                                  Inside — {d().scans.inside.lighthouseName || "Unknown"}
                                </span>
                              </div>
                              <div class={styles.legendItem}>
                                <div
                                  class={styles.legendLine}
                                  style={{ background: COLOR_OUTSIDE }}
                                />
                                <span>Outside centroid</span>
                              </div>
                              <div class={styles.legendItem}>
                                <div
                                  class={styles.legendLine}
                                  style={{ background: COLOR_INSIDE }}
                                />
                                <span>Inside centroid</span>
                              </div>
                            </div>
                          </div>

                          {/* RSSI scatter (algorithm 2 only) */}
                          <Show
                            when={
                              d().event.algorithmId === "rssi_weighted_centroid" &&
                              (d().scans.inside.scans.some((s) => s.rssiDbm !== null) ||
                                d().scans.outside.scans.some((s) => s.rssiDbm !== null))
                            }
                          >
                            {(() => {
                              const rssiMeta = meta.rssiTrend as {
                                outside: { slope: number; r2: number };
                                inside: { slope: number; r2: number };
                              } | undefined;
                              return (
                                <div class={styles.chartSection}>
                                  <p class={styles.chartTitle}>RSSI Over Time</p>
                                  <RssiScatterChart
                                    inside={d().scans.inside.scans}
                                    outside={d().scans.outside.scans}
                                    startMs={startMs}
                                    durationMs={durationMs}
                                    outsideSlope={rssiMeta?.outside.slope ?? 0}
                                    insideSlope={rssiMeta?.inside.slope ?? 0}
                                  />
                                  <div class={styles.legend}>
                                    <div class={styles.legendItem}>
                                      <div
                                        class={styles.legendDot}
                                        style={{ background: COLOR_OUTSIDE }}
                                      />
                                      <span>Outside scans</span>
                                    </div>
                                    <div class={styles.legendItem}>
                                      <div
                                        class={styles.legendDot}
                                        style={{ background: COLOR_INSIDE }}
                                      />
                                      <span>Inside scans</span>
                                    </div>
                                    <div class={styles.legendItem}>
                                      <div
                                        class={styles.legendLine}
                                        style={{
                                          background: COLOR_OUTSIDE,
                                          "border-top": "2px dashed",
                                        }}
                                      />
                                      <span>Outside trend</span>
                                    </div>
                                    <div class={styles.legendItem}>
                                      <div
                                        class={styles.legendLine}
                                        style={{
                                          background: COLOR_INSIDE,
                                          "border-top": "2px dashed",
                                        }}
                                      />
                                      <span>Inside trend</span>
                                    </div>
                                  </div>
                                </div>
                              );
                            })()}
                          </Show>
                        </>
                      );
                    })()}
                  </Show>
                </Show>
              </>
            )}
          </Show>
        </div>
      </div>
    </div>
  );
};
