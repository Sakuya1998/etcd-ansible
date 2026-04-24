# solo-etcd-ansible（生产级 etcd v3.5）

这是一套用于生产环境的 etcd v3.5 Ansible 部署/运维工程，支持：
- 单节点 / 多节点（推荐 3/5）
- Ubuntu/Debian + RHEL 系混合发行版
- mTLS（client & peer 双向认证）
- systemd 托管
- 健康检查、滚动升级（leader last）
- 定期 snapshot 备份 + 保留策略 + 远端持久化（S3/OSS/NFS）
- 定期 defrag（错峰）
- Prometheus 抓取示例 + 告警规则 + Runbook

## 目录
- `inventories/prod/`：示例 inventory
- `roles/etcd/`：核心部署与运维逻辑
- `roles/etcd_pki/`：可选证书策略（BYO/auto）
- `playbooks/`：常用运维 playbook

## 快速开始
1) 编辑 inventory：
- `inventories/prod/hosts.yml`：填写 etcd 节点与 `ansible_host`
- `inventories/prod/group_vars/etcd.yml`：填写版本、目录、备份/defrag 周期等

默认目录约定（可覆写）：
- data-dir：`/data/etcd/data`
- wal-dir：`/data/etcd/wal`
- 配置：`/data/etcd/config`
- PKI：`/data/etcd/pki`
- 日志：`/data/etcd/logs/etcd.log`（并提供 logrotate）
- 备份：`/data/etcd/backup`（可选远端持久化 S3/OSS/NFS）

2) 准备证书（强烈建议生产启用 mTLS）
### 方案 A：BYO（默认推荐）
在 `inventories/prod/group_vars/etcd.yml` 或各节点 `host_vars/` 中填入：
- `etcd_ca_crt`
- `etcd_server_crt` / `etcd_server_key`
- `etcd_peer_crt` / `etcd_peer_key`
- `etcd_client_crt` / `etcd_client_key`（给本机 etcdctl、备份/defrag 脚本使用）

建议用 `ansible-vault` 加密私钥。

### 方案 B：auto（自动签发，可选）
将 `etcd_pki_mode: auto`，并确保控制端安装 Ansible collection：
```bash
ansible-galaxy collection install community.crypto
```
注意：自动签发会在控制端 `etcd_pki_base_dir/<cluster>`（默认 `/root/.ansible/etcd-pki/<cluster>`）生成 CA 与证书；生产使用前请评估安全合规要求，并确保目录权限为 0700。

3) 新集群初始化（Bootstrap，推荐）
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-bootstrap.yml
```

4) 已存在集群的“配置收敛/修复”（Deploy）
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-deploy.yml
```

5) 健康检查
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-health.yml
```

## 滚动升级（leader last）
修改 `etcd_version`（以及 tarball/checksum），然后执行：
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-upgrade.yml
```

## 手动触发一次快照
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-snapshot.yml
```
说明：只有 leader 节点会执行 `etcdctl snapshot save`，非 leader 会自动跳过。

## 扩容 / 缩容 / 替换节点
扩容（新增节点加入集群）：
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-member-add.yml \
  --extra-vars 'etcd_new_members=["etcd-4","etcd-5"]'
```

缩容（移除节点）：
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-member-remove.yml \
  --extra-vars 'etcd_remove_members=["etcd-5"]'
```

替换节点（默认：add 新 → 稳定 → remove 旧）：
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-member-replace.yml \
  --extra-vars 'etcd_old_member=etcd-2 etcd_new_member=etcd-2-new'
```

## TLS 证书轮转（无停机优先）
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-cert-rotate.yml \
  --extra-vars 'etcd_cert_rotate=true'
```
可选：`etcd_cert_rotate_mode=rolling_restart` 会按 followers→leader last 滚动重启，强制刷新 peer 连接。

## 恢复（高风险）
恢复会停止 etcd 并重建数据目录，仅建议在演练/灾备场景使用：
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-restore.yml \
  --extra-vars "i_know_restore_will_stop_etcd=true etcd_restore_snapshot=/var/backups/etcd/snapshot-xxx.db"
```

## Prometheus 抓取示例
见：
- 抓取：`docs/prometheus/scrape-etcd.yml`
- 告警：`docs/prometheus/alerts-etcd.yml`（或 `docs/prometheus/prometheusrule-etcd.yaml`）
- Runbook：`docs/prometheus/runbooks-etcd.md`

说明：默认 metrics 端口会监听 `0.0.0.0:2381`，生产务必通过防火墙/安全组限制来源；也可通过 `etcd_metrics_listen_urls` 收敛监听地址。

## 压测与容量规划
见 `docs/perf-and-capacity.md`。

## Docker Compose 集成测试
见 `tests/docker-compose/README.md`，或直接运行：
```bash
make test-docker-compose
```

TLS（auto PKI + 轮转）回归测试入口：
```bash
./tests/docker-compose/test-tls.sh
```
