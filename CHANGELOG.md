# Changelog

## 2026.11.18-stable

固定当前生产部署，作为后续新机器的基线。

### 固定内容

- 上游基线 `sergiuszm/ninfer-4090` @ `7f47a62282b8e9d3c3b03bd6750d0bfe37e9bb66`；
- 完整生产补丁 `patches/ninfer-4090-stable.patch`；
- Qwen3.8-27B container v2，revision `3526913004b1`；
- 262,144 上下文、1,048,576 KV、6 并发、A16、MTP3、K15 lookup、视觉 8192；
- 8003 / 8004 / 8005 三个独立实例的启动器、systemd 模板和验收脚本。

### 相比上一版部署包

- 补丁更新到包含 JSON `json_object` / `json_schema`、视觉输入、host KV、
  worker 原地恢复和 KV 分页预留的源码；
- 启动参数改为三个实例统一的 6 并发与 16 GiB host KV；
- 删除旧的双实例文档、旧补丁和启动脚本 tar 包，避免和当前版本混淆；
- 新增 `start-8003/8004/8005.sh`、`stop-ninfer.sh`、`healthcheck.sh`、
  `smoke-test.sh`、`health-watchdog.sh` 和 systemd 模板；
- 文档去除本机绝对路径、内网地址、主机名和密钥；
- 明确 `fast` / `pure` / `baseline` 三个 profile 的边界。

### 已知边界

- 单卡单实例，不做多卡张量并行；
- DFlash 不支持 JSON Schema，生产默认 MTP3；
- 8 并发是硬上限，6 并发是推荐折中；
- 缓存不跨实例、不跨重启；
- 参考 tok/s 是验证机读数，新机必须重新验收。
