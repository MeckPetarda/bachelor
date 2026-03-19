import { createStore } from "solid-js/store";
import * as api from "../api";
import type { CreateUserRequest, UpdateUserRequest, User } from "../types";
import { showToast } from "./toast";

interface UsersState {
  users: User[];
  loading: boolean;
  error: string | null;
}

const [state, setState] = createStore<UsersState>({
  users: [],
  loading: false,
  error: null,
});

export async function fetchAll() {
  setState({ loading: true, error: null });
  try {
    const res = await api.getUsers();
    setState({ users: res.data, loading: false });
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to fetch users";
    setState({ error: message, loading: false });
    showToast(message, "error");
  }
}

export async function createUser(data: CreateUserRequest) {
  console.log("data", data);

  try {
    const user = await api.createUser(data);

    console.log("<<<<<<<<<", user);

    setState("users", (users) => [...users, user]);
    showToast(`Users "${data.name}" created`, "success");
    return user;
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to create user";
    showToast(message, "error");
    throw err;
  }
}

export async function updateUser(id: string, data: UpdateUserRequest) {
  try {
    const updated = await api.updateUser(id, data);
    setState("users", (g) => g.id === id, updated);
    showToast("User updated", "success");
    return updated;
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to update user";
    showToast(message, "error");
    throw err;
  }
}

export async function deleteUser(id: string) {
  try {
    await api.deleteUser(id);
    setState("users", (users) => users.filter((g) => g.id !== id));
    showToast("User deleted", "success");
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Failed to delete user";
    showToast(message, "error");
    throw err;
  }
}

export { state as usersState };
