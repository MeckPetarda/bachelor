export type Placement = 'STANDALONE' | 'INSIDE' | 'OUTSIDE';
export type ScanSource = 'realtime' | 'offline_sync';

export interface Health {
  uptimeSec: number;
  freeHeapBytes: number;
  wifiRssiDbm: number;
  rfidState: string;
  rfidIsResponsive: boolean;
}

export interface RuntimeStatus {
  isConnected: boolean;
  lastHealthAt: string | null;
  health: Health | null;
}

export interface GroupInfo {
  id: number;
  label: string;
}

export interface Lighthouse {
  id: number;
  name: string;
  deviceId: string;
  label: string | null;
  placement: Placement;
  firmwareVersion: string | null;
  isActive: boolean;
  createdAt: string;
  group: GroupInfo | null;
  runtime: RuntimeStatus | null;
}

export interface PendingDevice {
  deviceId: string;
  isConnected: boolean;
  firstSeenAt: string;
  lastHealthAt: string | null;
  health: Health | null;
}

export interface GroupMember {
  id: number;
  name: string;
  deviceId: string;
  placement: Placement;
}

export interface Group {
  id: number;
  label: string;
  description: string | null;
  members: GroupMember[];
  createdAt: string;
  updatedAt: string;
}

export interface Scan {
  id: string;
  lighthouseId: number;
  lighthouseName: string;
  epc: string;
  rssiDbm: number;
  timestamp: string;
  source: ScanSource;
  receivedAt: string;
}

export interface ClaimDeviceRequest {
  name: string;
  label?: string;
  placement: Placement;
  groupId?: number | null;
}

export interface CreateGroupRequest {
  label: string;
  description?: string;
}

export interface UpdateGroupRequest {
  label?: string;
  description?: string;
}

export interface UpdateLighthouseRequest {
  name?: string;
  label?: string;
  placement?: Placement;
  groupId?: number | null;
}

export interface ScansFilter {
  lighthouseId?: number;
  epc?: string;
  source?: ScanSource;
  from?: string;
  to?: string;
  limit?: number;
  offset?: number;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  limit: number;
  offset: number;
}

export interface ListResponse<T> {
  data: T[];
  count: number;
}

// WebSocket message types
export type WsMessageType =
  | 'scan'
  | 'device:online'
  | 'device:offline'
  | 'device:health'
  | 'device:pending';

export interface WsMessage<T = unknown> {
  type: WsMessageType;
  payload: T;
  timestamp: string;
}

export interface WsScanPayload {
  id: string;
  lighthouseId: number;
  lighthouseName: string;
  epc: string;
  rssiDbm: number;
  timestamp: string;
  source: ScanSource;
}

export interface WsDeviceOnlinePayload {
  deviceId: string;
  lighthouseId: number | null;
}

export interface WsDeviceOfflinePayload {
  deviceId: string;
  lighthouseId: number | null;
  isGraceful: boolean;
}

export interface WsDeviceHealthPayload {
  deviceId: string;
  lighthouseId: number | null;
  health: Health;
}

export interface WsDevicePendingPayload {
  deviceId: string;
}
