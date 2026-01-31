import { Component, For, Show, createSignal, onMount } from 'solid-js';
import { LighthouseCard } from '../components/LighthouseCard';
import { PendingDeviceCard } from '../components/PendingDeviceCard';
import { ClaimModal } from '../components/ClaimModal';
import {
  lighthousesState,
  fetchAll as fetchLighthouses,
  claimDevice,
} from '../stores/lighthouses';
import { groupsState, fetchAll as fetchGroups } from '../stores/groups';
import type { PendingDevice, ClaimDeviceRequest } from '../types';
import styles from './Lighthouses.module.css';

export const Lighthouses: Component = () => {
  const [claimingDevice, setClaimingDevice] = createSignal<PendingDevice | null>(null);

  onMount(() => {
    fetchLighthouses();
    fetchGroups();
  });

  const handleClaim = async (data: ClaimDeviceRequest) => {
    const device = claimingDevice();
    if (!device) return;

    await claimDevice(device.deviceId, data);
  };

  return (
    <div class={styles.page}>
      <Show when={lighthousesState.pending.length > 0}>
        <section class={styles.section}>
          <div class="section-header">
            <h2 class="section-title">Pending Devices</h2>
            <span class="count-badge">{lighthousesState.pending.length}</span>
          </div>
          <div class={`grid grid-3 ${styles.grid}`}>
            <For each={lighthousesState.pending}>
              {(device) => (
                <PendingDeviceCard
                  device={device}
                  onClaim={() => setClaimingDevice(device)}
                />
              )}
            </For>
          </div>
        </section>
      </Show>

      <section class={styles.section}>
        <div class="section-header">
          <h2 class="section-title">Registered Lighthouses</h2>
          <span class="count-badge">{lighthousesState.registered.length}</span>
        </div>

        <Show
          when={!lighthousesState.loading}
          fallback={<div class={styles.loading}>Loading lighthouses...</div>}
        >
          <Show
            when={lighthousesState.registered.length > 0}
            fallback={
              <div class={styles.empty}>
                No lighthouses registered yet. Connect a device to get started.
              </div>
            }
          >
            <div class={`grid grid-2 ${styles.grid}`}>
              <For each={lighthousesState.registered}>
                {(lighthouse) => <LighthouseCard lighthouse={lighthouse} />}
              </For>
            </div>
          </Show>
        </Show>
      </section>

      <Show when={claimingDevice()}>
        <ClaimModal
          device={claimingDevice()!}
          groups={groupsState.groups}
          onClose={() => setClaimingDevice(null)}
          onSubmit={handleClaim}
        />
      </Show>
    </div>
  );
};
