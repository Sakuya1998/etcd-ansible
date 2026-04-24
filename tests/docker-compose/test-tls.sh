#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

compose="docker compose"

echo "[INFO] Build images"
$compose build

echo "[INFO] Start containers"
$compose up -d

cleanup() {
  echo "[INFO] Stopping containers"
  $compose down -v || true
}
trap cleanup EXIT

echo "[INFO] Wait for SSH to be ready"
ssh_ready=0
for i in {1..60}; do
  if $compose exec -T ansible bash -lc 'sshpass -p ansible ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@etcd1 "echo ok" >/dev/null 2>&1'; then
    ssh_ready=1
    break
  fi
  sleep 1
done
if [[ "$ssh_ready" -ne 1 ]]; then
  echo "[ERROR] SSH is not ready (cannot reach etcd1 from ansible container)."
  echo "[ERROR] Hint: check docker DNS/aliases for etcd1/etcd2/etcd3 in docker-compose network."
  exit 1
fi

echo "[INFO] Bootstrap etcd cluster with TLS (auto PKI)"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker-tls/hosts.yml playbooks/etcd-bootstrap.yml'

echo "[INFO] Rotate certificates (hot reload) and validate health"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker-tls/hosts.yml playbooks/etcd-cert-rotate.yml --extra-vars "etcd_cert_rotate=true etcd_cert_force_rotate=true etcd_cert_rotate_mode=hot_reload"'

echo "[INFO] Health check"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker-tls/hosts.yml playbooks/etcd-health.yml'

echo "[INFO] PASS"
