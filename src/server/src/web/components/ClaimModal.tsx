import { type Component, createSignal, For, Show } from 'solid-js';
import type { PendingDevice, Group, Placement } from '../types';
import styles from './Modal.module.css';

interface Props {
  device: PendingDevice;
  groups: Group[];
  onClose: () => void;
  onSubmit: (data: {
    name: string;
    label?: string;
    placement: Placement;
    groupId?: number;
  }) => Promise<void>;
}

export const ClaimModal: Component<Props> = (props) => {
  const [name, setName] = createSignal('');
  const [label, setLabel] = createSignal('');
  const [placement, setPlacement] = createSignal<Placement>('STANDALONE');
  const [groupId, setGroupId] = createSignal<string>('');
  const [error, setError] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);

  const availableGroups = () =>
    props.groups.filter((g) => g.members.length < 2);

  const handleSubmit = async (e: Event) => {
    e.preventDefault();
    setError('');

    if (!name().trim()) {
      setError('Name is required');
      return;
    }

    setSubmitting(true);
    try {
      await props.onSubmit({
        name: name().trim(),
        label: label().trim() || undefined,
        placement: placement(),
        groupId: groupId() ? parseInt(groupId(), 10) : undefined,
      });
      props.onClose();
    } catch (err) {
      if (err instanceof Error) {
        setError(err.message);
      } else {
        setError('Failed to claim device');
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div class={styles.overlay} onClick={props.onClose}>
      <div class={styles.modal} onClick={(e) => e.stopPropagation()}>
        <div class={styles.header}>
          <h2 class={styles.title}>Claim Device</h2>
          <button class={styles.closeBtn} onClick={props.onClose}>
            \u00D7
          </button>
        </div>

        <div class={styles.deviceInfo}>
          <span class={styles.deviceLabel}>Device ID:</span>
          <code>{props.device.deviceId}</code>
        </div>

        <form onSubmit={handleSubmit}>
          <div class={styles.field}>
            <label class="label">Name *</label>
            <input
              type="text"
              class="input"
              value={name()}
              onInput={(e) => setName(e.currentTarget.value)}
              placeholder="e.g., Front Door Inside"
              required
            />
          </div>

          <div class={styles.field}>
            <label class="label">Label (optional)</label>
            <input
              type="text"
              class="input"
              value={label()}
              onInput={(e) => setLabel(e.currentTarget.value)}
              placeholder="e.g., Front Door - Inside Sensor"
            />
          </div>

          <div class={styles.field}>
            <label class="label">Placement *</label>
            <select
              class="select"
              value={placement()}
              onChange={(e) => setPlacement(e.currentTarget.value as Placement)}
            >
              <option value="STANDALONE">Standalone</option>
              <option value="INSIDE">Inside</option>
              <option value="OUTSIDE">Outside</option>
            </select>
          </div>

          <div class={styles.field}>
            <label class="label">Group (optional)</label>
            <select
              class="select"
              value={groupId()}
              onChange={(e) => setGroupId(e.currentTarget.value)}
            >
              <option value="">No group</option>
              <For each={availableGroups()}>
                {(group) => (
                  <option value={group.id}>
                    {group.label} ({group.members.length}/2)
                  </option>
                )}
              </For>
            </select>
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
              {submitting() ? 'Claiming...' : 'Claim Device'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
