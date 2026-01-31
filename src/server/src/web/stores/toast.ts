import { createSignal } from 'solid-js';

export type ToastType = 'success' | 'error' | 'info' | 'warning';

export interface Toast {
  id: number;
  message: string;
  type: ToastType;
}

let nextId = 0;

const [toasts, setToasts] = createSignal<Toast[]>([]);

export function showToast(message: string, type: ToastType = 'info') {
  const id = nextId++;
  const toast: Toast = { id, message, type };

  setToasts((prev) => [...prev, toast]);

  // Auto-dismiss after 4 seconds
  setTimeout(() => {
    dismissToast(id);
  }, 4000);
}

export function dismissToast(id: number) {
  setToasts((prev) => prev.filter((t) => t.id !== id));
}

export { toasts };
