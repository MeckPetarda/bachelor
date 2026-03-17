import { type Component, createSignal, Show } from "solid-js";
import type { Group } from "../types";
import styles from "./Modal.module.css";

interface Props {
  group?: Group;
  onClose: () => void;
  onSubmit: (data: { label: string; description?: string }) => Promise<void>;
}

export const GroupModal: Component<Props> = (props) => {
  const [label, setLabel] = createSignal(props.group?.label ?? "");
  const [description, setDescription] = createSignal(
    props.group?.description ?? "",
  );
  const [error, setError] = createSignal("");
  const [submitting, setSubmitting] = createSignal(false);

  const isEdit = () => !!props.group;

  const handleSubmit = async (e: Event) => {
    e.preventDefault();
    setError("");

    if (!label().trim()) {
      setError("Label is required");
      return;
    }

    setSubmitting(true);
    try {
      await props.onSubmit({
        label: label().trim(),
        description: description().trim() || undefined,
      });
      props.onClose();
    } catch (err) {
      if (err instanceof Error) {
        setError(err.message);
      } else {
        setError("Failed to save group");
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div class={styles.overlay} onClick={props.onClose}>
      <div class={styles.modal} onClick={(e) => e.stopPropagation()}>
        <div class={styles.header}>
          <h2 class={styles.title}>
            {isEdit() ? "Edit Group" : "Create Group"}
          </h2>
          <button class={styles.closeBtn} onClick={props.onClose}>
            \u00D7
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          <div class={styles.field}>
            <label class="label">Label *</label>
            <input
              type="text"
              class="input"
              value={label()}
              onInput={(e) => setLabel(e.currentTarget.value)}
              placeholder="e.g., Main Entrance"
              required
            />
          </div>

          <div class={styles.field}>
            <label class="label">Description (optional)</label>
            <textarea
              class="input"
              rows={3}
              value={description()}
              onInput={(e) => setDescription(e.currentTarget.value)}
              placeholder="e.g., Building A front door"
            />
          </div>

          <Show when={error()}>
            <div class={styles.error}>{error()}</div>
          </Show>

          <div class={styles.actions}>
            <button
              type="button"
              class="btn btn-secondary"
              onClick={props.onClose}
            >
              Cancel
            </button>
            <button
              type="submit"
              class="btn btn-primary"
              disabled={submitting()}
            >
              {submitting() ? "Saving..." : isEdit() ? "Save" : "Create"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
