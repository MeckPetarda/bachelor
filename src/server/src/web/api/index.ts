import { get, post, patch, del } from "./client";
import type {
  Lighthouse,
  PendingDevice,
  Group,
  Scan,
  ClaimDeviceRequest,
  CreateGroupRequest,
  UpdateGroupRequest,
  UpdateLighthouseRequest,
  ScansFilter,
  PaginatedResponse,
  ListResponse,
  User,
  CreateUserRequest,
  UpdateUserRequest,
  ProcessedEvent,
  ProcessedEventDetail,
  ProcessedEventsFilter,
} from "../types";

// Lighthouses
export function getLighthouses(): Promise<ListResponse<Lighthouse>> {
  return get<ListResponse<Lighthouse>>("/lighthouses/all");
}

export function updateLighthouse(
  id: number,
  data: UpdateLighthouseRequest,
): Promise<Lighthouse> {
  return patch<Lighthouse>(`/lighthouses/${id}/update`, data);
}

// Pending devices
export function getPendingDevices(): Promise<ListResponse<PendingDevice>> {
  return get<ListResponse<PendingDevice>>("/devices/pending");
}

export function claimDevice(
  deviceId: string,
  data: ClaimDeviceRequest,
): Promise<Lighthouse> {
  return post<Lighthouse>(
    `/devices/pending/${encodeURIComponent(deviceId)}/claim`,
    data,
  );
}

// Groups
export function getGroups(): Promise<ListResponse<Group>> {
  return get<ListResponse<Group>>("/groups");
}

export function getGroup(id: number): Promise<Group> {
  return get<Group>(`/groups/${id}`);
}

export function createGroup(data: CreateGroupRequest): Promise<Group> {
  return post<Group>("/groups", data);
}

export function updateGroup(
  id: number,
  data: UpdateGroupRequest,
): Promise<Group> {
  return patch<Group>(`/groups/${id}`, data);
}

export function deleteGroup(id: number): Promise<void> {
  return del<void>(`/groups/${id}`);
}

// Scans
export function getScans(
  filters: ScansFilter = {},
): Promise<PaginatedResponse<Scan>> {
  const params = new URLSearchParams();

  if (filters.lighthouseId !== undefined) {
    params.set("lighthouseId", String(filters.lighthouseId));
  }
  if (filters.epc) {
    params.set("epc", filters.epc);
  }
  if (filters.source) {
    params.set("source", filters.source);
  }
  if (filters.from) {
    params.set("from", filters.from);
  }
  if (filters.to) {
    params.set("to", filters.to);
  }
  if (filters.limit !== undefined) {
    params.set("limit", String(filters.limit));
  }
  if (filters.offset !== undefined) {
    params.set("offset", String(filters.offset));
  }

  const query = params.toString();
  const path = query ? `/scans?${query}` : "/scans";
  return get<PaginatedResponse<Scan>>(path);
}

// Users
export function getUsers(): Promise<ListResponse<User>> {
  return get<ListResponse<User>>("/users");
}

export function getUser(id: string): Promise<User> {
  return get<User>(`/users/${id}`);
}

export function createUser(data: CreateUserRequest): Promise<User> {
  return post<User>("/users", data);
}

export function updateUser(id: string, data: UpdateUserRequest): Promise<User> {
  return patch<User>(`/users/${id}`, data);
}

export function deleteUser(id: string): Promise<void> {
  return del<void>(`/users/${id}`);
}

// Processed events
export function getProcessedEvents(
  filters: ProcessedEventsFilter,
): Promise<PaginatedResponse<ProcessedEvent>> {
  const params = new URLSearchParams();
  params.set("algorithmId", filters.algorithmId);
  if (filters.groupId !== undefined)
    params.set("groupId", String(filters.groupId));
  if (filters.userId) params.set("userId", filters.userId);
  if (filters.tagEpc) params.set("tagEpc", filters.tagEpc);
  if (filters.direction) params.set("direction", filters.direction);
  if (filters.from) params.set("from", filters.from);
  if (filters.to) params.set("to", filters.to);
  if (filters.minConfidence !== undefined)
    params.set("minConfidence", String(filters.minConfidence));
  if (filters.limit !== undefined) params.set("limit", String(filters.limit));
  if (filters.offset !== undefined)
    params.set("offset", String(filters.offset));
  return get<PaginatedResponse<ProcessedEvent>>(`/events?${params.toString()}`);
}

export function getProcessedEventDetail(
  id: string,
): Promise<ProcessedEventDetail> {
  return get<ProcessedEventDetail>(`/events/${id}`);
}
