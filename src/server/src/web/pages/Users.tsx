import { type Component, createSignal, Show } from "solid-js";

import styles from "./Users.module.css";
import { UserModal } from "../components/UserModal";
import { UsersTable } from "../components/UsersTable";
import type { User } from "../types";

export const Users: Component = () => {
  const [showModal, setShowModal] = createSignal(false);
  const [editUser, setEditUser] = createSignal<User | undefined>();

  const openCreateModal = () => {
    setShowModal(true);
  };

  const mockUser: User = {
    id: 1,
    name: "Jane Smith",
    tags: ["E2003412B8E6A1C5F0024D9A", "E2004701C3F8B2D6A1053E8C"],
    sync_id: 42,
    email: "jane.smith@example.com",
    active: true,
  };

  const mockUsers: User[] = [mockUser];

  return (
    <div class={styles.page}>
      <div class="page-header">
        <h1 class="page-title">Users</h1>
        <button class="btn btn-primary" onClick={openCreateModal}>
          Create User
        </button>
      </div>

      <UsersTable
        users={mockUsers}
        loading={false}
        onEdit={(u) => {
          setEditUser(u);
          setShowModal(true);
        }}
      />

      <Show when={showModal()}>
        <UserModal
          user={editUser()}
          onClose={() => {
            setShowModal(false);
            setEditUser(undefined);
          }}
          onSubmit={async (data) => {
            console.log(data);
          }}
        />
      </Show>
    </div>
  );
};
