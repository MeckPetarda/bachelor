import { type Component, createSignal, Show, onMount } from "solid-js";

import styles from "./Users.module.css";
import { UserModal } from "../components/UserModal";
import { UsersTable } from "../components/UsersTable";
import type { User } from "../types";
import {
  createUser,
  deleteUser,
  fetchAll,
  updateUser,
  usersState,
} from "../stores/users";

export const Users: Component = () => {
  const [showModal, setShowModal] = createSignal(false);
  const [editingUser, setEditingUser] = createSignal<User | undefined>();

  onMount(() => {
    fetchAll();
  });

  const openCreateModal = () => {
    setEditingUser(undefined);
    setShowModal(true);
  };

  const openEditModal = (user: User) => {
    setEditingUser(user);
    setShowModal(true);
  };

  const closeModal = () => {
    setShowModal(false);
    setEditingUser(undefined);
  };

  const handleSubmit = async (data: User) => {
    const user = editingUser();
    if (user) {
      if (!user.id)
        throw new Error(
          "How do you want me to updates something without an id???",
        );

      await updateUser(user.id, data);
    } else {
      await createUser(data);
    }
  };

  const handleDelete = async (user: User) => {
    if (!user.id)
      throw new Error(
        "How do you want me to updates something without an id???",
      );

    await deleteUser(user.id);
  };

  const mockUser: User = {
    id: "-sasdss",
    name: "Jane Smith",
    tags: ["E2003412B8E6A1C5F0024D9A", "E2004701C3F8B2D6A1053E8C"],
    sync_id: "42",
    email: "jane.smith@example.com",
    isActive: true,
  };

  return (
    <div class={styles.page}>
      <div class="page-header">
        <h1 class="page-title">Users</h1>
        <button class="btn btn-primary" onClick={openCreateModal}>
          Create User
        </button>
      </div>

      <UsersTable
        users={usersState.users}
        loading={usersState.loading}
        onEdit={(u) => openEditModal(u)}
        onDelete={handleDelete}
      />

      <Show when={showModal()}>
        <UserModal
          user={editingUser()}
          onClose={() => closeModal()}
          onSubmit={handleSubmit}
        />
      </Show>
    </div>
  );
};
