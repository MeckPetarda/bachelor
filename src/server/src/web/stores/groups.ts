import { createStore } from 'solid-js/store';
import * as api from '../api';
import { showToast } from './toast';
import type { Group, CreateGroupRequest, UpdateGroupRequest } from '../types';

interface GroupsState {
  groups: Group[];
  loading: boolean;
  error: string | null;
}

const [state, setState] = createStore<GroupsState>({
  groups: [],
  loading: false,
  error: null,
});

export async function fetchAll() {
  setState({ loading: true, error: null });
  try {
    const res = await api.getGroups();
    setState({ groups: res.data, loading: false });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Failed to fetch groups';
    setState({ error: message, loading: false });
    showToast(message, 'error');
  }
}

export async function createGroup(data: CreateGroupRequest) {
  try {
    const group = await api.createGroup(data);
    setState('groups', (groups) => [...groups, group]);
    showToast(`Group "${data.label}" created`, 'success');
    return group;
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Failed to create group';
    showToast(message, 'error');
    throw err;
  }
}

export async function updateGroup(id: number, data: UpdateGroupRequest) {
  try {
    const updated = await api.updateGroup(id, data);
    setState('groups', (g) => g.id === id, updated);
    showToast('Group updated', 'success');
    return updated;
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Failed to update group';
    showToast(message, 'error');
    throw err;
  }
}

export async function removeGroup(id: number) {
  try {
    await api.deleteGroup(id);
    setState('groups', (groups) => groups.filter((g) => g.id !== id));
    showToast('Group deleted', 'success');
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Failed to delete group';
    showToast(message, 'error');
    throw err;
  }
}

export { state as groupsState };
