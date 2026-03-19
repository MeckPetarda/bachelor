import { type Component, createSignal, Show } from "solid-js";
import type { User } from "../types";
import styles from "./Modal.module.css";
import { Toggle } from "./Toggle";
import { TagsInput } from "./TagsInput";

interface Props {
  user?: User;
  onClose: () => void;
  onSubmit: (data: UserFormData) => Promise<void>;
}

export interface UserFormData {
  name?: string;
  tags: string[];
  sync_id: number;
  email?: string;
  active: boolean;
}

export const UserModal: Component<Props> = (props) => {
  const [name, setName] = createSignal(props.user?.name ?? "");
  const [tags, setTags] = createSignal<string[]>(props.user?.tags ?? []);
  const [syncId, setSyncId] = createSignal(
    props.user?.sync_id != null ? String(props.user.sync_id) : "",
  );
  const [email, setEmail] = createSignal(props.user?.email ?? "");
  const [active, setActive] = createSignal(props.user?.active ?? true);
  const [error, setError] = createSignal("");
  const [submitting, setSubmitting] = createSignal(false);

  const isEdit = () => !!props.user;

  const handleSubmit = async (e: Event) => {
    e.preventDefault();
    setError("");

    const syncIdNum = parseInt(syncId(), 10);
    if (!syncId().trim() || isNaN(syncIdNum)) {
      setError("Sync ID is required and must be a whole number");
      return;
    }

    const emailVal = email().trim();
    if (emailVal && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailVal)) {
      setError("Email address is not valid");
      return;
    }

    setSubmitting(true);
    try {
      await props.onSubmit({
        name: name().trim() || undefined,
        tags: tags(),
        sync_id: syncIdNum,
        email: emailVal || undefined,
        active: active(),
      });
      props.onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save user");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div class={styles.overlay} onClick={props.onClose}>
      <div class={styles.modal} onClick={(e) => e.stopPropagation()}>
        <div class={styles.header}>
          <h2 class={styles.title}>{isEdit() ? "Edit User" : "Create User"}</h2>
          <button class={styles.closeBtn} onClick={props.onClose}>
            &#215;
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          {/* Name */}
          <div class={styles.field}>
            <label class="label">
              Name{" "}
              <span class={styles.hint}>
                (optional — implied from RFID if absent)
              </span>
            </label>
            <input
              type="text"
              class="input"
              value={name()}
              onInput={(e) => setName(e.currentTarget.value)}
              placeholder="e.g., Jane Smith"
            />
          </div>

          {/* Sync ID */}
          <div class={styles.field}>
            <label class="label">Sync ID *</label>
            <input
              type="number"
              class="input"
              value={syncId()}
              onInput={(e) => setSyncId(e.currentTarget.value)}
              placeholder="Remote system user ID"
              required
              step="1"
            />
          </div>

          {/* Email */}
          <div class={styles.field}>
            <label class="label">
              Email <span class={styles.hint}>(optional)</span>
            </label>
            <input
              type="email"
              class="input"
              value={email()}
              onInput={(e) => setEmail(e.currentTarget.value)}
              placeholder="user@example.com"
            />
          </div>

          {/* RFID Tags */}
          <div class={styles.field}>
            <label class="label">
              RFID Tags <span class={styles.hint}>(EPC strings)</span>
            </label>
            <TagsInput value={tags()} onChange={setTags} />
          </div>

          {/* Active toggle */}
          <div class={`${styles.field} ${styles.fieldInline}`}>
            <span class="label">Active</span>
            <Toggle
              id="user-active"
              checked={active()}
              onChange={setActive}
              label={active() ? "Enabled" : "Disabled"}
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
              {submitting() ? "Saving…" : isEdit() ? "Save" : "Create"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
