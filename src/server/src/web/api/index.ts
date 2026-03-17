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
