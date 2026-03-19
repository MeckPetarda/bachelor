import { type Component, For, Show } from "solid-js";
import type { User } from "../types";
import styles from "./UsersTable.module.css";

interface Props {
  users: User[];
  loading: boolean;
  onEdit: (user: User) => void;
}

export const UsersTable: Component<Props> = (props) => {
  return (
    <div class={styles.container}>
      <Show when={props.loading}>
        <div class={styles.loading}>Loading...</div>
      </Show>

      <Show when={!props.loading && props.users.length === 0}>
        <div class={styles.empty}>No users found</div>
      </Show>

      <Show when={!props.loading && props.users.length > 0}>
        <table class={styles.table}>
          <thead>
            <tr>
              <th>Name</th>
              <th>Sync ID</th>
              <th>Email</th>
              <th>Tags</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <For each={props.users}>
              {(user) => (
                <tr>
                  <td>
                    <Show
                      when={user.name}
                      fallback={<span class={styles.implied}>From RFID</span>}
                    >
                      {user.name}
                    </Show>
                  </td>
                  <td class={styles.mono}>{user.sync_id}</td>
                  <td class={styles.email}>
                    <Show
                      when={user.email}
                      fallback={<span class={styles.implied}>—</span>}
                    >
                      {user.email}
                    </Show>
                  </td>
                  <td>
                    <Show
                      when={user.tags.length > 0}
                      fallback={<span class={styles.implied}>None</span>}
                    >
                      <div class={styles.tags}>
                        <For each={user.tags}>
                          {(tag) => <span class={styles.tag}>{tag}</span>}
                        </For>
                      </div>
                    </Show>
                  </td>
                  <td>
                    <Show
                      when={user.isActive}
                      fallback={
                        <span class="badge badge-warning">Inactive</span>
                      }
                    >
                      <span class="badge badge-success">Active</span>
                    </Show>
                  </td>
                  <td class={styles.actions}>
                    <button
                      class="btn btn-secondary"
                      onClick={() => props.onEdit(user)}
                    >
                      Edit
                    </button>
                  </td>
                </tr>
              )}
            </For>
          </tbody>
        </table>
      </Show>
    </div>
  );
};
