import { createLogger } from "../utils/logger";
import { runRetrySweep } from "./navigo3/navigo3Service";

const logger = createLogger("Navigo3Poller");

const DEFAULT_INTERVAL_MS = 60000;

let intervalHandle: ReturnType<typeof setInterval> | null = null;
let sweepInProgress = false;

export function startNavigo3Poller(): void {
  if (intervalHandle !== null) {
    logger.warn("Navigo3 poller already running");
    return;
  }

  const rawInterval = parseInt(process.env.NAVIGO3_RETRY_INTERVAL_MS ?? "");
  const intervalMs =
    Number.isFinite(rawInterval) && rawInterval > 0
      ? rawInterval
      : DEFAULT_INTERVAL_MS;

  intervalHandle = setInterval(() => {
    if (sweepInProgress) return;
    sweepInProgress = true;
    runRetrySweep()
      .catch((err) => logger.error("Navigo3 retry sweep error:", err))
      .finally(() => {
        sweepInProgress = false;
      });
  }, intervalMs);

  logger.info(`Navigo3 poller started (interval=${intervalMs}ms)`);
}

export function stopNavigo3Poller(): void {
  if (intervalHandle === null) return;
  clearInterval(intervalHandle);
  intervalHandle = null;
  logger.info("Navigo3 poller stopped");
}
