#!/usr/bin/env bash
#
# Lifecycle manager for the lab VM.
#
# The VM is a real Ubuntu cloud image booted with QEMU/KVM in user-mode
# networking. Nothing here needs root: no libvirt daemon, no bridge, no sudo.
# Ports are forwarded from the host loopback so the operator host can reach the
# guest without exposing it to the local network.
#
#   ./scripts/vm.sh up        create (if needed) and boot the VM
#   ./scripts/vm.sh ssh       open a shell as the admin user
#   ./scripts/vm.sh status    show PID, SSH and forwarded ports
#   ./scripts/vm.sh stop      graceful poweroff
#   ./scripts/vm.sh destroy   poweroff and delete the disk and seed ISO
#
# Environment:
#   VM_CPUS     vCPUs (default 2)
#   VM_MEMORY   MiB of RAM (default 2048)
#   VM_DISK     virtual disk size (default 12G)
#   SSH_PORT    host port -> guest 22   (default 2222)
#   NODE_PORT   host port -> guest 9100 (default 19100)
#   APP_PORT    host port -> guest 8080 (default 18080, firewall test)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="${ROOT}/.cache/vm"
IMAGE_NAME="noble-server-cloudimg-amd64.img"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/${IMAGE_NAME}"
IMAGE="${VM_DIR}/${IMAGE_NAME}"
DISK="${VM_DIR}/sre-lab.qcow2"
SEED="${VM_DIR}/seed.iso"
KEY="${VM_DIR}/id_ed25519"
PUBKEY="${KEY}.pub"
PIDFILE="${VM_DIR}/qemu.pid"
CONSOLE="${VM_DIR}/console.log"
MONITOR="${VM_DIR}/monitor.sock"

VM_CPUS="${VM_CPUS:-2}"
VM_MEMORY="${VM_MEMORY:-2048}"
VM_DISK="${VM_DISK:-12G}"
SSH_PORT="${SSH_PORT:-2222}"
NODE_PORT="${NODE_PORT:-19100}"
APP_PORT="${APP_PORT:-18080}"

ADMIN_USER="sre"
SSH_OPTS=(
  -i "${KEY}"
  -p "${SSH_PORT}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=5
  -o LogLevel=ERROR
)

log() { printf '[vm] %s\n' "$*" >&2; }
die() { printf '[vm] error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

require_tools() {
  local missing=()
  for tool in qemu-system-x86_64 qemu-img xorriso ssh ssh-keygen curl; do
    have "${tool}" || missing+=("${tool}")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "missing tools: ${missing[*]}"
  fi
  [ -r /dev/kvm ] || die "/dev/kvm is not readable; KVM is required"
}

is_running() {
  [ -f "${PIDFILE}" ] || return 1
  local pid
  pid="$(cat "${PIDFILE}" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  # A stale PID file must never stop an unrelated host process.
  [ -r "/proc/${pid}/cmdline" ] || return 1
  tr '\0' '\n' < "/proc/${pid}/cmdline" | grep -Fxq "file=${DISK},if=virtio,format=qcow2"
}

ensure_image() {
  mkdir -p "${VM_DIR}"
  if [ -f "${IMAGE}" ]; then
    return 0
  fi
  log "downloading Ubuntu 24.04 cloud image (~600 MB, one time)"
  local tmp="${IMAGE}.part"
  curl -fL --retry 3 --retry-delay 2 -o "${tmp}" "${IMAGE_URL}"
  mv "${tmp}" "${IMAGE}"
}

ensure_key() {
  mkdir -p "${VM_DIR}"
  if [ -f "${KEY}" ]; then
    return 0
  fi
  log "generating lab SSH key ${KEY}"
  ssh-keygen -q -t ed25519 -N "" -C "sre-lab" -f "${KEY}"
  chmod 600 "${KEY}"
}

render_seed() {
  local work
  work="$(mktemp -d)"

  local pubkey
  pubkey="$(cat "${PUBKEY}")"
  sed "s|__SSH_PUBKEY__|${pubkey}|" "${ROOT}/vm/user-data.yaml.tpl" > "${work}/user-data"
  cp "${ROOT}/vm/meta-data" "${work}/meta-data"

  if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds "${SEED}" "${work}/user-data" "${work}/meta-data"
  else
    xorriso -as mkisofs \
      -output "${SEED}" \
      -volid CIDATA \
      -joliet -rock \
      "${work}/user-data" "${work}/meta-data" >/dev/null 2>&1 \
      || die "failed to build the cloud-init seed ISO"
  fi
  rm -rf "${work}"
}

create_disk() {
  [ -f "${DISK}" ] && return 0
  ensure_image
  log "creating ${VM_DISK} disk backed by the cached image"
  qemu-img create -q -f qcow2 -F qcow2 -b "${IMAGE}" "${DISK}" "${VM_DISK}"
}

start_vm() {
  if is_running; then
    log "already running (pid $(cat "${PIDFILE}"))"
    return 0
  fi
  ensure_image
  ensure_key
  render_seed
  create_disk
  rm -f "${MONITOR}" "${CONSOLE}"

  log "booting ${VM_CPUS} vCPU / ${VM_MEMORY} MiB"
  qemu-system-x86_64 \
    -name sre-lab \
    -machine q35,accel=kvm \
    -cpu host \
    -smp "${VM_CPUS}" \
    -m "${VM_MEMORY}" \
    -object rng-random,filename=/dev/urandom,id=rng0 \
    -device virtio-rng-pci,rng=rng0 \
    -drive "file=${DISK},if=virtio,format=qcow2" \
    -drive "file=${SEED},media=cdrom,format=raw,readonly=on" \
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22,hostfwd=tcp:127.0.0.1:${NODE_PORT}-:9100,hostfwd=tcp:127.0.0.1:${APP_PORT}-:8080" \
    -display none \
    -serial "file:${CONSOLE}" \
    -monitor "unix:${MONITOR},server,nowait" \
    -daemonize \
    -pidfile "${PIDFILE}"

  log "waiting for SSH on 127.0.0.1:${SSH_PORT}"
  local deadline=$((SECONDS + 300))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    if ssh "${SSH_OPTS[@]}" "${ADMIN_USER}@127.0.0.1" true 2>/dev/null; then
      log "VM ready"
      return 0
    fi
    sleep 2
  done
  tail -20 "${CONSOLE}" >&2 || true
  die "VM did not become reachable in 300s"
}

stop_vm() {
  if ! is_running; then
    log "not running"
    rm -f "${PIDFILE}"
    return 0
  fi
  log "requesting graceful shutdown"
  ssh "${SSH_OPTS[@]}" "${ADMIN_USER}@127.0.0.1" "sudo poweroff" 2>/dev/null || true
  local deadline=$((SECONDS + 45))
  while is_running && [ "${SECONDS}" -lt "${deadline}" ]; do
    sleep 2
  done
  if is_running; then
    log "graceful shutdown timed out; killing"
    kill "$(cat "${PIDFILE}")" 2>/dev/null || true
    sleep 2
  fi
  rm -f "${PIDFILE}"
}

status_vm() {
  if is_running; then
    echo "state:   running (pid $(cat "${PIDFILE}"))"
  else
    echo "state:   stopped"
  fi
  echo "disk:    ${DISK}"
  echo "console: ${CONSOLE}"
  echo "ssh:     ssh -i ${KEY} -p ${SSH_PORT} ${ADMIN_USER}@127.0.0.1"
  echo "ports:   127.0.0.1:${SSH_PORT}->22, 127.0.0.1:${NODE_PORT}->9100, 127.0.0.1:${APP_PORT}->8080"
  if is_running; then
    printf 'ssh:     '
    if ssh "${SSH_OPTS[@]}" "${ADMIN_USER}@127.0.0.1" "echo reachable" 2>/dev/null; then :; else echo "unreachable"; fi
  fi
}

destroy_vm() {
  stop_vm
  rm -f "${DISK}" "${SEED}" "${CONSOLE}" "${PIDFILE}" "${MONITOR}"
  log "disk and seed removed (cached image and key kept)"
}

wait_ssh() {
  local deadline=$((SECONDS + 120))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    if ssh "${SSH_OPTS[@]}" "${ADMIN_USER}@127.0.0.1" true 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  die "SSH is not reachable; run './scripts/vm.sh status'"
}

ssh_cmd() {
  wait_ssh
  exec ssh "${SSH_OPTS[@]}" "${ADMIN_USER}@127.0.0.1" "$@"
}

main() {
  local action="${1:-help}"
  case "${action}" in
    up)        require_tools; start_vm ;;
    stop)      stop_vm ;;
    destroy)   destroy_vm ;;
    status)    status_vm ;;
    ssh)       shift; ssh_cmd "$@" ;;
    wait)      require_tools; wait_ssh ;;
    console)   tail -f "${CONSOLE}" ;;
    help|*)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
  esac
}

main "$@"
