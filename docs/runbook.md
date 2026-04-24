# etcd 运维 Runbook（配套 solo-etcd-ansible）

## 1. 变更前检查（建议）
1) 集群健康：
- `ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-health.yml`
2) 磁盘空间与 IO（尤其是 data-dir/wal-dir）
3) 备份（至少一次 leader snapshot）：
- `ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-snapshot.yml`

## 1.1 新集群初始化（Bootstrap）
- `ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-bootstrap.yml`
说明：bootstrap 使用“初始化锁 + member add + 串行 join”流程，避免一次性 bootstrap 失败形成脏集群。

## 2. 滚动升级 SOP（leader last）
1) 更新 `etcd_version`（及离线包/校验值）
2) 执行：
- `ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-upgrade.yml`
3) 验证：
- endpoint status/health 全绿
- version 一致

## 2.1 TLS 轮转（无停机优先）
- `ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-cert-rotate.yml --extra-vars 'etcd_cert_rotate=true'`
可选：`etcd_cert_rotate_mode=rolling_restart` 触发 followers→leader last 滚动重启。

## 2.2 扩容/缩容/替换节点
- 扩容：`playbooks/etcd-member-add.yml`
- 缩容：`playbooks/etcd-member-remove.yml`
- 替换：`playbooks/etcd-member-replace.yml`

## 3. 备份策略建议
- 备份目录：默认 `/data/etcd/backup`（可通过 `etcd_backup_dir` 覆写）
- 备份周期：至少 hourly 或 daily（视业务而定）
- 保留策略：按数量与/或按天
- 建议将快照异地/对象存储保存（本工程已支持 S3/OSS/NFS，可在 group_vars 配置 `etcd_snapshot_backend`）

### 3.1 远端备份凭据治理（重要）
1) **禁止明文提交**：S3/OSS 的 AK/SK 等敏感变量应使用 `ansible-vault` 或外部 Secret（Ansible Controller / CI Secret）管理。  
2) **落盘权限收敛**：本工程会将凭据写入 `{{ etcd_conf_dir }}/etcd-snapshot.env`，权限应为 `0600 root:root`。  
3) **最小权限**：为对象存储创建专用凭据，仅允许对指定 bucket/prefix 进行 `PutObject/GetObject/ListBucket`（或等价权限），避免全桶/全账号权限。  
4) **轮转 SOP**：轮转 AK/SK 后，先手动触发一次快照验证上传成功，再恢复定时任务；同时保留一段“旧凭据回滚窗口”（按组织策略）。  

## 4. defrag 注意事项（重要）
- defrag 会阻塞单节点的读写；必须错峰/串行，避开业务高峰。
- 建议依赖 etcd 的 auto-compaction（或手动 compact）后再 defrag 才能真正回收空间。
- 本工程默认：每节点本地 defrag + systemd timer 的 RandomizedDelaySec，降低同时触发概率。

## 4.1 日志策略（建议）
默认配置为 `stderr + 文件日志`（`/data/etcd/logs/etcd.log`），并通过 logrotate 做轮转。  
注意：
- 文件日志轮转默认使用 `copytruncate`（避免 etcd 不重开文件导致日志继续写到旧文件），但在高写入场景可能带来**短暂 IO 抖动/少量丢日志**风险。  
- 生产更推荐：只输出到 `stderr`（journald）并由集中采集系统收集；文件日志作为可选。  

## 5. 灾备恢复（演练优先）
恢复会重建数据目录与 member/cluster ID，风险极高：
1) 确认快照文件在每个节点可访问
2) 执行恢复 playbook（需显式确认变量）
3) 恢复后做全量健康检查并验证业务一致性

### 5.1 revision 回退风险（Kubernetes/informer 场景重点）
etcd 从快照恢复后，可能出现 revision 低于“快照之后客户端见过的 revision”，导致 watch/informer 缓存异常。
可通过恢复参数避免 revision 下降：
- `etcd_restore_bump_revision`：对快照当前 revision 增加一个偏移
- `etcd_restore_mark_compacted: true`：与 bump 配合，标记 compaction 点以终止旧 watch

示例（演练环境）：
```bash
ansible-playbook -i inventories/prod/hosts.yml playbooks/etcd-restore.yml \
  --extra-vars "i_know_restore_will_stop_etcd=true etcd_restore_snapshot=/data/etcd/backup/snapshot-xxx.db etcd_restore_bump_revision=100000 etcd_restore_mark_compacted=true"
```

## 6. 监控与告警
- Prometheus 抓取示例：`docs/prometheus/scrape-etcd.yml`
- 告警规则：
  - 裸 Prometheus：`docs/prometheus/alerts-etcd.yml`
  - Prometheus Operator：`docs/prometheus/prometheusrule-etcd.yaml`
- 处置 Runbook：`docs/prometheus/runbooks-etcd.md`

### 6.1 metrics 端口网络准入（重要）
本工程默认 `listen-metrics-urls` 监听 `0.0.0.0:2381`（便于 Prometheus 抓取），但这会扩大暴露面。
生产环境务必通过 **防火墙/安全组/ACL** 限制访问来源（建议仅允许运维监控系统网段访问）。
如需收敛监听地址，可设置：
- `etcd_metrics_listen_urls: "https://127.0.0.1:2381"`（仅本机）
- 或监听监控网卡 IP
