#!/usr/bin/env bash
# setup-ntp.sh — Install and configure chrony as the LAN NTP server
#
# Run as root on the Lighthouse server machine (the same host running BunJS,
# MQTT broker, and PostgreSQL).
#
# Usage:
#   sudo bash scripts/setup-ntp.sh
#
# Verification after running:
#   chronyc tracking          — check synchronisation status
#   chronyc sources           — list upstream NTP sources
#   From another LAN machine:
#     ntpdate -q <server_ip>  — confirm NTP responses are received
#
# NTP uses UDP port 123 (standard, not configurable in chrony).

set -euo pipefail

CHRONY_CONF_SRC="$(dirname "$0")/../src/server/config/chrony.conf"
CHRONY_CONF_DST="/etc/chrony/chrony.conf"
CHRONY_CONF_DST_ALT="/etc/chrony.conf"   # path on some distros (RHEL/CentOS)

# ─── Helper functions ─────────────────────────────────────────────────────────

log()  { echo "[NTP setup] $*"; }
err()  { echo "[NTP setup] ERROR: $*" >&2; exit 1; }
warn() { echo "[NTP setup] WARNING: $*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (use sudo)."
  fi
}

detect_package_manager() {
  if command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  else
    err "Unsupported package manager. Install chrony manually and re-run."
  fi
}

install_chrony() {
  local pm
  pm=$(detect_package_manager)
  log "Detected package manager: $pm"

  if command -v chronyc &>/dev/null; then
    log "chrony is already installed ($(chronyc --version 2>&1 | head -1))."
    return 0
  fi

  log "Installing chrony..."
  case "$pm" in
    apt)
      # Disable any running ntpd/systemd-timesyncd to avoid port conflicts
      systemctl stop systemd-timesyncd 2>/dev/null || true
      systemctl disable systemd-timesyncd 2>/dev/null || true
      apt-get update -qq
      apt-get install -y chrony
      ;;
    dnf|yum)
      "$pm" install -y chrony
      ;;
  esac
  log "chrony installed."
}

deploy_config() {
  local src="$1"
  local dst

  if [[ ! -f "$src" ]]; then
    err "Config source not found: $src"
  fi

  # Determine destination path (distro-dependent)
  if [[ -d /etc/chrony ]]; then
    dst="$CHRONY_CONF_DST"
  else
    dst="$CHRONY_CONF_DST_ALT"
  fi

  log "Deploying config: $src → $dst"

  # Back up existing config if it differs
  if [[ -f "$dst" ]] && ! diff -q "$src" "$dst" &>/dev/null; then
    local backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$dst" "$backup"
    log "Backed up existing config to: $backup"
  fi

  cp "$src" "$dst"
  log "Config deployed."
}

enable_and_restart() {
  log "Enabling and restarting chronyd..."
  systemctl enable chronyd 2>/dev/null || systemctl enable chrony 2>/dev/null || warn "Could not enable chrony service."
  systemctl restart chronyd 2>/dev/null || systemctl restart chrony 2>/dev/null || err "Failed to start chrony service."
  log "chronyd is running."
}

open_firewall() {
  # Attempt to open UDP 123 if ufw or firewalld is active.
  # Skip silently if neither is active.
  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    log "Opening UDP 123 in ufw..."
    ufw allow 123/udp
  elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    log "Opening UDP 123 in firewalld..."
    firewall-cmd --permanent --add-service=ntp
    firewall-cmd --reload
  else
    log "No active firewall detected — skipping firewall rule."
  fi
}

verify() {
  log "Waiting for chrony to synchronise (up to 10 s)..."
  sleep 3

  if chronyc tracking &>/dev/null; then
    log "chronyc tracking output:"
    chronyc tracking
  else
    warn "chronyc not responding yet — may need more time to sync."
  fi

  log ""
  log "Setup complete."
  log ""
  log "Verify from another LAN machine:"
  log "  ntpdate -q \$(hostname -I | awk '{print \$1}')"
  log ""
  log "Or check status locally at any time:"
  log "  chronyc tracking"
  log "  chronyc sources"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

require_root
install_chrony
deploy_config "$CHRONY_CONF_SRC"
open_firewall
enable_and_restart
verify
