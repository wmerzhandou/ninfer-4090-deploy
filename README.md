# NInfer · Qwen3.8-27B · RTX 4090 48G 稳定部署包

这是一个**可复现的部署层**：固定上游源码基线、生产补丁、启动参数、健康检查、
systemd 单元和排障手册。模型权重、编译产物、密钥、内网地址和原始请求日志都不进
仓库。

目标硬件是单机多张 **RTX 4090 48 GB**。本机验证的形态是：每张卡跑一个独立
NInfer 实例，三个生产实例分别监听 `8003`、`8004`、`8005`，不启用多卡张量并行。

## 固定版本

| 项目 | 固定值 |
|---|---|
| 上游基线 | `sergiuszm/ninfer-4090`，`rtx4090-port`，commit `7f47a62282b8e9d3c3b03bd6750d0bfe37e9bb66` |
| 生产补丁 | [`patches/ninfer-4090-stable.patch`](patches/ninfer-4090-stable.patch) |
| 补丁 SHA-256 | 见 [`checksums.txt`](checksums.txt) |
| 模型工件 | Qwen3.8-27B NInfer，container v2，16.96 GiB |
| 模型 revision | `3526913004b1` |
| 模型 SHA-256 | `eec39564993d6e9c7d5e383382a760f093465c9d163ec9a1bd6b80199514bf3e` |
| 验证过的生产二进制 SHA-256 | `b1e33b9b74f12a9fa075a0dbb0e26823f69ff5678006434137b080efefb61d97` |
| 二进制大小 | `686,150,664` bytes |

> 生产二进制只作为校验锚点，不随仓库分发。新机器应从补丁重新构建，并用本仓库的
> 验收脚本确认行为。补丁相对上游基线包含 149 个文件、约 4.7 万行新增（其中约
> 1.8 MB 是裁剪后的 XGrammar 源码）。

## 固定参数

三个生产实例使用同一组参数，仅端口和 `CUDA_VISIBLE_DEVICES` 不同：

```text
--max-context 262144
--kv-capacity 1048576
--max-concurrency 6
--max-pending-requests 16
--pending-timeout-ms 600000
--max-private-continuations 32
--max-shared-prefixes 12
--host-state-slots 16
--host-kv-mib 16384
--prefill-chunk 2048
--kv-dtype rk4v4-e8
--default-max-tokens 65536
--prefill-activations a16
--spec mtp
--draft-tokens 3
--lm-head-draft
--prompt-lookup-tokens 15
--prompt-lookup-min-match 12
--vision
--vision-max-tokens 8192
--no-cuda-graph
--device 0
```

`--device 0` 是实例内部的逻辑编号；物理卡由 `CUDA_VISIBLE_DEVICES` 选择。不要把两者
同时改成不同的物理编号。

`fast` 档包含 MTP3 + K15 prompt lookup；`pure` 档只保留 MTP3，用于需要和基线做
逐字节对照的场景；`baseline` 档关闭投机解码和 lookup，只用于诊断。生产默认是
`fast`，但所有改动都应先过 `pure` 的回归。

## 已验证能力

- OpenAI Chat Completions 与 Responses API，含 SSE 流式输出；
- `response_format` 的 `text`、`json_object`、`json_schema`，由 XGrammar 在采样前
  施加 token mask，不是生成后重试；
- 图片/视频输入（`--vision`），视觉 scratchpad 上限 8192 token；
- 262,144 token 原生上下文，`rk4v4-e8` KV 量化；
- MTP3 投机解码，K15 prompt lookup（复制型编辑、长前缀重读收益明显）；
- 单实例多请求并发，推荐 6 路，引擎硬上限 8 路；
- 实例内前缀缓存、Responses 会话续接和 `prompt_cache_key` 私有续接；
- worker 异常原地恢复、KV 分页 entitlement 预留、失败正文落日志；
- systemd 用户服务与健康看门狗。

## 参考实测

以下是验证机（4 × RTX 4090 48 GB，450 W，驱动 590.48.01，CUDA 12.8.61，GCC
13.4.0）的历史读数，用于新机对照，不是跨硬件常数：

| 场景 | 读数 |
|---|---:|
| 32K prefill，E8 KV | 约 2,030 tok/s |
| 1 路 decode | 约 165 tok/s |
| 4 路聚合并发 | 约 297 tok/s，TTFT 中位数约 5.2 s |
| 6 路聚合并发 | 约 398–399 tok/s，TTFT 中位数约 7.3 s |
| 8 路聚合并发 | 约 496 tok/s，TTFT 中位数约 10.0 s |
| 复制型编辑 fixture，K15 vs MTP3 | 193.9 vs 170.0 tok/s |
| 207K token 热重读 | 约 73 ms，缓存命中 99.997% |
| Codex 真实任务 5 项 | 5/5 通过，平均 decode 126.42 tok/s |
| dsh 真实任务 5 项 | 5/5 通过，平均 decode 120.36 tok/s |

新机器必须重新跑 [`scripts/smoke-test.sh`](scripts/smoke-test.sh)。驱动、功耗上限、
散热、模型 SHA 或 CUDA 版本不同，读数就不能直接混排。

## 快速开始

### 1. 取代码并应用补丁

```bash
git clone https://github.com/sergiuszm/ninfer-4090.git
cd ninfer-4090
git switch -c 4090-stable 7f47a62282b8e9d3c3b03bd6750d0bfe37e9bb66
git apply --3way /path/to/ninfer-4090-deploy/patches/ninfer-4090-stable.patch
```

### 2. 下载并校验模型

```bash
NINFER_MODEL_DIR="$PWD/models" \
  /path/to/ninfer-4090-deploy/scripts/download-model.sh
```

脚本固定 revision `3526913004b1` 并强制校验 SHA-256。`main` revision 已经是
container v3，本引擎会报 `artifact magic is not NInfer v2`，不要使用。

### 3. 构建

```bash
CC=/usr/bin/gcc-13 CXX=/usr/bin/g++-13 \
CUDACXX=/usr/local/cuda-12.8/bin/nvcc \
  /path/to/ninfer-4090-deploy/scripts/build.sh
```

产物默认在 `build/apps/ninfer-serve`。完整依赖和已验证的 conda 构建方式见
[`docs/部署指南.md`](docs/部署指南.md)。

### 4. 起实例

```bash
export NINFER_SERVER="$PWD/build/apps/ninfer-serve"
export NINFER_MODEL="$PWD/models/qwen3_8_27b.ninfer"
export NINFER_API_KEY="replace-with-a-private-key"

/path/to/ninfer-4090-deploy/scripts/start-8003.sh
/path/to/ninfer-4090-deploy/scripts/start-8004.sh
/path/to/ninfer-4090-deploy/scripts/start-8005.sh
```

默认映射：

| 实例 | 物理 GPU | 端口 |
|---|---:|---:|
| `8003` | 1 | 8003 |
| `8004` | 2 | 8004 |
| `8005` | 0 | 8005 |

如果机器的卡号不同，用 `NINFER_GPU` 或 `--gpu` 覆盖。不要并发启动同一张卡上的
两个实例。

第四张卡可以用通用启动器另起实例（不会自动启用）：

```bash
/path/to/ninfer-4090-deploy/scripts/start-ninfer.sh --port 8006 --gpu 3
```

### 5. 验收

```bash
/path/to/ninfer-4090-deploy/scripts/healthcheck.sh

NINFER_BASE_URL=http://127.0.0.1:8003/v1 \
NINFER_API_KEY="replace-with-a-private-key" \
  /path/to/ninfer-4090-deploy/scripts/smoke-test.sh
```

## 客户端接入

服务暴露 OpenAI 兼容端点：

```text
base_url: http://<SERVER_IP>:8003/v1
model:    qwen3.8-27b
api_key:  启动时设置的 NINFER_API_KEY
```

`8003`、`8004`、`8005` 是三个独立实例，缓存和会话不共享。同一个长会话应固定指向
同一个端口；多个客户端可以各连一个端口，避免互相争抢同一实例的并发槽。

Codex、dsh 的配置字段以各自版本文档为准；核心就是 OpenAI 兼容的 `base_url`、
`api_key` 和 `model`。流式请求使用 `stream: true`，Responses 客户端使用
`/v1/responses`。

## 仓库结构

```text
patches/       上游基线到生产源码的完整补丁
scripts/       下载、构建、启动、停止、健康检查、验收、看门狗
systemd/       用户级 systemd 模板
config/        三个实例的 env 示例与完整参数模板
docs/          部署、参数、实测、排障
licenses/      XGrammar 等第三方许可与归属
SECURITY.md    内网部署的安全边界
```

## 重要边界

- 这是**单卡单实例**方案，不做多卡张量并行；
- 不引入 container v3；不使用 DFlash2 作为默认后端（JSON 约束在 DFlash 上会明确报
  `unsupported_json_schema`）；
- INT8 prefill、因果分块等实验特性没有进入默认生产参数；
- `--prefill-chunk` 保持 `2048`，不要为了追求读数改成大于 `2688`；
- 并发硬上限是 8；6 路是延迟与吞吐的折中，不是越多越好；
- 需要严格逐字节复现时使用 `pure` 档，并记录模型 SHA、KV dtype、采样参数和 commit。

## 来源与许可

- 上游引擎：[sergiuszm/ninfer-4090](https://github.com/sergiuszm/ninfer-4090)
- 3090 家族参考：[Don-Chad/ninfer-3090](https://github.com/Don-Chad/ninfer-3090)
- 更上游：[Neroued/ninfer](https://github.com/Neroued/ninfer)
- XGrammar：[mlc-ai/xgrammar](https://github.com/mlc-ai/xgrammar)

本仓库是部署 overlay，不替代上游项目。源码和第三方组件的版权、许可与归属见
[`LICENSE`](LICENSE)、[`NOTICE`](NOTICE) 和 [`licenses/`](licenses/)。
