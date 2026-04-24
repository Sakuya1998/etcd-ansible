#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if docker compose version >/dev/null 2>&1; then
  # docker compose v2：可叠加 v2 专用覆盖文件（启用 cgroupns_mode 等能力）
  compose="docker compose -f docker-compose.yml -f docker-compose.v2.yml"
else
  # docker-compose v1：不支持 cgroupns_mode，使用基础 compose 文件
  compose="docker-compose -f docker-compose.yml"
fi

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
  if $compose exec -T ansible bash -lc 'sshpass -p ansible ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ansible@solo-etcd1 "echo ok" >/dev/null 2>&1'; then
    ssh_ready=1
    break
  fi
  sleep 1
done
if [[ "$ssh_ready" -ne 1 ]]; then
  echo "[ERROR] SSH is not ready (cannot reach etcd1 from ansible container)."
  echo "[ERROR] Hint: check docker DNS/aliases for solo-etcd1/solo-etcd2/solo-etcd3 in docker-compose network."
  exit 1
fi

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
