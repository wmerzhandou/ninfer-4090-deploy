# NInfer on dual RTX 4090 48G

Deployment overlay and verified tuning profile for running **Qwen3.8-27B** with
[sergiuszm/ninfer-4090](https://github.com/sergiuszm/ninfer-4090) on two
RTX 4090 48 GB cards.

This repository is a sanitized deployment package. It contains the source patch,
startup scripts, measured results, and the full deployment guide. It does **not**
contain model weights, compiled binaries, raw client logs, credentials, hostnames,
IP addresses, GPU UUIDs, or absolute paths from the verification machine.

## Verified profile

- NVIDIA RTX 4090 48 GB x2, 450 W power limit
- CUDA 12.8+, GCC 13, `CMAKE_CUDA_ARCHITECTURES=89`
- Model artifact: 16.96 GiB container-v2 file
- Model SHA-256: `eec39564993d6e9c7d5e383382a760f093465c9d163ec9a1bd6b80199514bf3e`
- Context: 262,144 tokens
- KV: `rk4v4-e8`
- Prefill: A16, chunk 2048
- Decode: MTP3, three draft tokens, LM-head draft
- Lookup: K15, minimum match 12

The recommended low-latency instance uses concurrency 4. The multi-session
instance uses concurrency 6 with a fixed 1,048,576-token KV pool. The engine hard
limit is 8 concurrent requests per instance.

## Quick start

```bash
git clone https://github.com/sergiuszm/ninfer-4090.git
cd ninfer-4090
git switch -c 4090-deploy 7f47a62282b8e9d3c3b03bd6750d0bfe37e9bb66
git apply --3way /path/to/ninfer-4090-deploy/bench/deploy/4090-from-origin.patch
cp -a /path/to/ninfer-4090-deploy/scripts/start-ninfer-*.sh scripts/

export NINFER_SERVER="$PWD/build-sergiuszm/apps/ninfer-serve"
export NINFER_MODEL="$PWD/models/qwen3_8_27b.ninfer"
export NINFER_API_KEY="replace-with-a-private-key"

./scripts/start-ninfer-8003-fast.sh
./scripts/start-ninfer-8005-fast.sh
```

Build instructions, client configuration, concurrency measurements, acceptance
checks, experiment history, and troubleshooting are in the
[deployment guide](docs/4090-双实例智能体部署指南.md).

## Measured results

| Workload | Result |
|---|---:|
| 32K prefill, E8 | ~2,032 tok/s baseline; ~2,000 tok/s with final profile |
| 8K prefill, INT8 experiment | +78.4%, but failed byte-exact regression; not default |
| 118K prefill, INT8 experiment | +51.1%, but not default |
| 1 request, 1024-token decode | 165 tok/s aggregate |
| 4 concurrent requests | 297 tok/s aggregate, 5.2 s median TTFT |
| 6 concurrent requests | 398-399 tok/s aggregate, 7.3-7.4 s median TTFT |
| 8 concurrent requests | 496 tok/s aggregate, 10.0 s median TTFT |
| Copy-heavy edit fixture | 193.9 tok/s with K15 vs 170.0 tok/s with MTP3 |
| 207K-token warm reread | ~73 ms, 99.997% cache hit |
| Codex real tasks | 5/5 passed, 126.42 tok/s mean decode |
| dsh real tasks | 5/5 passed, 120.36 tok/s mean decode |

These numbers are hardware- and workload-dependent. Re-run the acceptance checks
when the driver, power limit, model artifact, or CUDA toolchain differs.

## Attribution and license

The source engine and upstream port are by their respective authors:

- https://github.com/sergiuszm/ninfer-4090
- https://github.com/Don-Chad/ninfer-3090
- https://github.com/Neroued/ninfer

This repository contains a deployment overlay, not a replacement project. See
[LICENSE](LICENSE) and preserve upstream copyright notices when redistributing
the patched source.
