# etcd 压测与容量规划建议（生产必读）

## 1) 硬件与网络基线（关键）
etcd 对 **磁盘写入延迟** 和 **网络 RTT** 极其敏感，推荐：
- SSD / NVMe，低写延迟、稳定 fsync
- 低 RTT 网络、稳定带宽
- 避免 HDD / 高延迟网络 / 网络盘（容易引发选举抖动、写入延迟飙升）

官方硬件建议参考（v3.5）：https://etcd.io/docs/v3.5/op-guide/hardware/

## 2) 你需要规划哪些负载维度
1. 写入 QPS（PUT/Txn）  
2. key/value 平均大小与分布（大 value 会放大 I/O 压力）  
3. watcher 数量与 watch 事件速率（Kubernetes 场景尤为关键）  
4. revision 增长速度（影响 compact 策略与 DB 增长）  

## 3) 压测建议（最小可行）
### 3.1 存储基准（先测磁盘，再测 etcd）
- `fio` 测顺序写与 fsync 延迟（关注 p95/p99 延迟，不能只看平均值）
- 目标：p99 fsync 足够低且稳定（阈值需结合业务；可用告警规则做长期守护）

### 3.2 etcd 读写基准
- 建议在演练环境使用与你业务接近的模型压测（key/value 大小、txn 比例、并发连接数）
- 观察：
  - gRPC 请求延迟分位
  - `etcd_disk_wal_fsync_duration_seconds`（WAL fsync）
  - leader change 次数

## 4) compaction / defrag 策略建议
1) 建议启用 `auto-compaction`（本工程默认启用 periodic 模式）  
2) defrag 只能回收 compact 后产生的空洞空间  
3) defrag 会阻塞单节点读写：必须 **逐节点串行/错峰** 执行（本工程用 systemd timer + RandomizedDelaySec 降低同时触发概率）

## 5) 何时需要扩容/更换节点（经验触发条件）
推荐长期监控并设置告警（本工程提供 `docs/prometheus/alerts-etcd.yml`）：
- `etcd_server_has_leader == 0`（无 leader）
- leader change 频繁（网络/资源/IO 抖动）
- `etcd_disk_wal_fsync_duration_seconds` p99 持续过高（磁盘瓶颈）
- `etcd_mvcc_db_total_size_in_bytes` 增长过快或接近 quota（容量瓶颈/碎片问题）

当出现上述问题时，优先按顺序排查：
1) 磁盘延迟（是否共享盘/被其他进程打爆）  
2) 网络 RTT 与丢包  
3) compaction/defrag 策略是否合理  
4) 扩容（3→5）或替换节点到更优硬件  

