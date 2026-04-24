# etcd 告警 Runbook（简版）

本文配合：
- `docs/prometheus/alerts-etcd.yml`
- `docs/prometheus/prometheusrule-etcd.yaml`

## etcdNoLeader（严重）
**含义**：实例报告 `etcd_server_has_leader == 0`，集群无法对外提供稳定写入。  
**排查**：
1. 确认是否有多数节点不可达（网络/防火墙/机器故障）。
2. 看 leader 变更是否频繁（`etcd_server_leader_changes_seen_total`）。
3. 检查磁盘延迟（尤其是 WAL fsync），见 `etcdHighFsyncDurations`。

## etcdMembersDown（警告）
**含义**：集群成员不可用或 peer 发送失败率异常。  
**排查**：
1. 目标节点是否宕机/进程退出：`systemctl status etcd`
2. peer 端口 2380 是否可达（安全组/iptables/路由）。
3. TLS 是否过期/不匹配（证书 SAN、CA 是否一致）。

## etcdHighFsyncDurations（警告/严重）
**含义**：WAL fsync p99 延迟过高，可能引发选举抖动与写入延迟。  
**优先排查磁盘**：
1. 是否使用 HDD / 网络盘（强烈建议 SSD 与低延迟存储）。
2. 同机是否有高 IO 干扰进程（可考虑独占盘/独占节点或 systemd IO 限制）。
3. 参考 Prometheus Operator upstream runbook：  
   https://runbooks.prometheus-operator.dev/runbooks/etcd/etcdhighfsyncdurations/

## etcdDatabaseQuotaLowSpace（严重）
**含义**：DB 接近 quota，写入可能被禁用。  
**处置**：
1. 优先确认是否需要提升 quota（谨慎）。
2. 确认 compaction 是否在工作；必要时手动 compact + defrag。

## etcdDatabaseHighFragmentationRatio（警告）
**含义**：碎片率过高，建议 defrag 回收空间。  
**处置**：
1. 先 compact，再逐节点串行 defrag（避免集群整体抖动）。
2. 避开业务高峰。

