import { type Component, For } from "solid-js";
import { toasts, dismissToast, type ToastType } from "../stores/toast";
import styles from "./Toast.module.css";

const typeIcons: Record<ToastType, string> = {
  success: "\u2713",
  error: "\u2717",
  warning: "\u26A0",
  info: "\u2139",
};

export const Toast: Component = () => {
  return (
    <div class={styles.container}>
      <For each={toasts()}>
        {(toast) => (
          <div class={`${styles.toast} ${styles[toast.type]}`}>
            <span class={styles.icon}>{typeIcons[toast.type]}</span>
            <span class={styles.message}>{toast.message}</span>
            <button
              class={styles.close}
              onClick={() => dismissToast(toast.id)}
              aria-label="Dismiss"
            >
              \u00D7
            </button>
          </div>
        )}
      </For>
    </div>
  );
};
