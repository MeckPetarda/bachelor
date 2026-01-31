import { type Component, For, Show, createSignal, onMount } from 'solid-js';
import { GroupCard } from '../components/GroupCard';
import { GroupModal } from '../components/GroupModal';
import {
  groupsState,
  fetchAll,
  createGroup,
  updateGroup,
  removeGroup,
} from '../stores/groups';
import type { Group } from '../types';
import styles from './Groups.module.css';

export const Groups: Component = () => {
  const [showModal, setShowModal] = createSignal(false);
  const [editingGroup, setEditingGroup] = createSignal<Group | undefined>(undefined);

  onMount(() => {
    fetchAll();
  });

  const openCreateModal = () => {
    setEditingGroup(undefined);
    setShowModal(true);
  };

  const openEditModal = (group: Group) => {
    setEditingGroup(group);
    setShowModal(true);
  };

  const closeModal = () => {
    setShowModal(false);
    setEditingGroup(undefined);
  };

  const handleSubmit = async (data: { label: string; description?: string }) => {
    const group = editingGroup();
    if (group) {
      await updateGroup(group.id, data);
    } else {
      await createGroup(data);
    }
  };

  const handleDelete = async (group: Group) => {
    await removeGroup(group.id);
  };

  return (
    <div class={styles.page}>
      <div class="page-header">
        <h1 class="page-title">Lighthouse Groups</h1>
        <button class="btn btn-primary" onClick={openCreateModal}>
          Create Group
        </button>
      </div>

      <Show
        when={!groupsState.loading}
        fallback={<div class={styles.loading}>Loading groups...</div>}
      >
        <Show
          when={groupsState.groups.length > 0}
          fallback={
            <div class={styles.empty}>
              No groups yet. Create a group to pair lighthouses for direction detection.
            </div>
          }
        >
          <div class={`grid grid-2 ${styles.grid}`}>
            <For each={groupsState.groups}>
              {(group) => (
                <GroupCard
                  group={group}
                  onEdit={() => openEditModal(group)}
                  onDelete={() => handleDelete(group)}
                />
              )}
            </For>
          </div>
        </Show>
      </Show>

      <Show when={showModal()}>
        <GroupModal
          group={editingGroup()}
          onClose={closeModal}
          onSubmit={handleSubmit}
        />
      </Show>
    </div>
  );
};
