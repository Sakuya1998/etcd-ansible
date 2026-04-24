# Docker Compose 集成测试

该测试会用 docker-compose 拉起 4 个容器：
- `ansible`：Ansible 控制端（在容器内执行 playbook）
- `etcd1/etcd2/etcd3`：3 台“模拟主机”（systemd + sshd），用于跑 etcd role

## 前置条件
- 本机已安装 Docker + docker compose plugin

## 运行
在仓库根目录执行：
```bash
./tests/docker-compose/test.sh
```

说明：
- 非 TLS 测试 inventory 使用 `inventories/docker/`：
  - 默认关闭 TLS（减少证书准备复杂度）
  - 不启用 systemd timers（减少 timer 干扰）
  - 允许手动触发 snapshot（`etcd_snapshot_enabled: true`，但 `etcd_enable_timers: false`）

如遇到脚本不可执行，可使用：
```bash
bash tests/docker-compose/test.sh
```

## TLS（auto PKI）场景测试
在仓库根目录执行：
```bash
./tests/docker-compose/test-tls.sh
```

说明：
- TLS 测试 inventory 使用 `inventories/docker-tls/`（启用 TLS + `etcd_pki_mode: auto`）。
- 测试流程：
  1) `playbooks/etcd-bootstrap.yml` 初始化集群
  2) `playbooks/etcd-cert-rotate.yml` 执行证书轮转（默认 `hot_reload`）
  3) `playbooks/etcd-health.yml` 进行健康检查
- 用途：作为“启用 TLS + auto PKI 分发 + 证书轮转关键路径”的回归入口。

如遇到脚本不可执行，可使用：
```bash
bash tests/docker-compose/test-tls.sh
```
