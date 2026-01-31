import { Component, For, Show } from 'solid-js';
import type { Group } from '../types';
import styles from './GroupCard.module.css';

interface Props {
  group: Group;
  onEdit: () => void;
  onDelete: () => void;
}

export const GroupCard: Component<Props> = (props) => {
  return (
    <div class={styles.card}>
      <div class={styles.header}>
        <h3 class={styles.label}>{props.group.label}</h3>
        <div class={styles.actions}>
          <button class="btn btn-secondary btn-sm" onClick={props.onEdit}>
            Edit
          </button>
          <button class="btn btn-danger btn-sm" onClick={props.onDelete}>
            Delete
          </button>
        </div>
      </div>

      <Show when={props.group.description}>
        <p class={styles.description}>{props.group.description}</p>
      </Show>

      <div class={styles.members}>
        <span class={styles.membersLabel}>Members ({props.group.members.length}/2):</span>
        <Show
          when={props.group.members.length > 0}
          fallback={<span class={styles.noMembers}>No members assigned</span>}
        >
          <div class={styles.memberList}>
            <For each={props.group.members}>
              {(member) => (
                <div class={styles.member}>
                  <span class={styles.memberName}>{member.name}</span>
                  <span class={`badge ${placementBadgeClass(member.placement)}`}>
                    {member.placement}
                  </span>
                </div>
              )}
            </For>
          </div>
        </Show>
      </div>
    </div>
  );
};

function placementBadgeClass(placement: string): string {
  switch (placement) {
    case 'INSIDE':
      return 'badge-success';
    case 'OUTSIDE':
      return 'badge-warning';
    default:
      return 'badge-neutral';
  }
}
