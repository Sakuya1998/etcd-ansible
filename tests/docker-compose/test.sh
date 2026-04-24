#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

compose="docker-compose"

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
for i in {1..60}; do
  if $compose exec -T ansible bash -lc 'sshpass -p ansible ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@etcd1 "echo ok" >/dev/null 2>&1'; then
    break
  fi
  sleep 1
done

echo "[INFO] Ansible ping"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible -i inventories/docker/hosts.yml etcd -m ping'

echo "[INFO] Bootstrap etcd cluster"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker/hosts.yml playbooks/etcd-bootstrap.yml'

echo "[INFO] Deploy idempotency (run twice)"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker/hosts.yml playbooks/etcd-deploy.yml'
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker/hosts.yml playbooks/etcd-deploy.yml'

echo "[INFO] Health check"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker/hosts.yml playbooks/etcd-health.yml'

echo "[INFO] Snapshot once and validate"
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventories/docker/hosts.yml playbooks/etcd-snapshot.yml'
$compose exec -T ansible bash -lc 'ANSIBLE_STDOUT_CALLBACK=default ansible -i inventories/docker/hosts.yml etcd1 -m shell -a "ls -1t /data/etcd/backup/snapshot-*.db | head -1 && /usr/local/bin/etcdutl snapshot status \\$(ls -1t /data/etcd/backup/snapshot-*.db | head -1) -w table"'

echo "[INFO] PASS"
